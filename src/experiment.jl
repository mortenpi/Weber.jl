import Base: run
export Experiment, setup, run, experiment_trial, experiment_offset

const default_moment_resolution = 0.0015
const default_input_resolution = 1/60
const exp_width = 1024
const exp_height = 768

const experiment_context = Array{Nullable{Experiment}}()
experiment_context[] = Nullable()

# internal function, usd to find the current experiment
function get_experiment()
  if isnull(experiment_context[])
    error("Unknown experiment context, call me inside `setup` or during an"*
          " experiment.")
  else
    get(experiment_context[])
  end
end

"""
    experiment_trial()

Returns the current trial of the experiment.
"""
experiment_trial(exp) = exp.data.trial
experiment_trial() = experiment_trial(get_experiment())
experiment_offset(exp) = exp.data.offset
experiment_offset() = experiment_offset(get_experiment())


"""
   experiment_metadata() = Dict{Symbol,Any}()

Returns metadata for this experiment. You can store
global state, specific to this experiment, in this dictionary.
"""
experiment_metadata(exp) = exp.info.meta
experiment_metadata() = experiment_metadata(get_experiment())


"""
   Experiment([skip=0],[columns=[symbols...]],[debug=false],
              [moment_resolution=1/2000],[input_resolution=1/60],[data_dir="data"],
              [width=1024],[height=768],kwds...)

Prepares a new experiment to be run.

# Keyword Arguments
* skip: the number of offsets to skip. Allows restarting of an experiment.
* columns: the names (as symbols) of columns that will be recorded during
the experiment (using `record`).
* debug: if true experiment will show in a windowed view
* moment_resolution: the precision (in seconds) that moments
  should be presented at
* input_resolution: the precision (in seconds) that input events should
be queried.
* data_dir: the directory where data files should be stored
* width and height: specified the screen resolution during the experiment

Additional keyword arguments can be specified to store extra information to the
recorded data file, e.g. the experimental condition or the version of the
experiment being run.
"""
function Experiment(;skip=0,columns=Symbol[],debug=false,
                    moment_resolution = default_moment_resolution,
                    data_dir = "data",
                    null_window = false,
                    hide_output = false,
                    input_resolution = default_input_resolution,
                    width=exp_width,height=exp_height,info_values...)
  mkpath(data_dir)

  meta = Dict{Symbol,Any}()
  start_time = time()
  start_date = now()
  timestr = Dates.format(start_date,"yyyy-mm-dd__HH_MM_SS")
  info_str = join(map(x -> x[2],info_values),"_")
  filename = joinpath(data_dir,info_str*"_"*timestr*".csv")
  einfo = ExperimentInfo(info_values,meta,input_resolution,
                         moment_resolution,start_date,columns,filename,
                         hide_output)

  offset = 0
  trial = 0
  trial_watcher = (e) -> nothing
  last_time = 0.0
  pause_mode = Running
  moments = MomentQueue(Deque{Moment}(),0)
  submoments = Array{MomentQueue,1}()
  exception = Nullable{Tuple{Exception,Array{Ptr{Void}}}}()
  cleanup = () -> error("no cleanup function available!")
  last_good_delta = -1
  last_bad_delta = -1
  data = ExperimentData(offset,trial,skip,last_time,trial_watcher,pause_mode,moments,
                        submoments,exception,cleanup,last_good_delta,
                        last_bad_delta)

  flags = ExperimentFlags(false,false)

  win = window(width,height,fullscreen=!debug,accel=!debug,null=null_window)

  Experiment(einfo,data,flags,win)
end


"""
    setup(fn,experiment)

Setup the experiment, adding breaks, practice, and trials.

Setup creats the context necessary to generate elements of an expeirment. All
calls to `addtrial`, `addbreak` and `addpractice` must be called in side of
`fn`. This function must be called before `run`.
"""
function setup(fn::Function,exp::Experiment)
  # create data file header
  record_header(exp)
  function cleanup()
    exp.flags.running = false
    exp.flags.processing = false
    close(exp.win)

    # gc is disabled during individual trials (and enabled at the end of
    # a trial). Make sure it really does return to an enabled state.
    gc_enable(true)
  end

  try
    # the first moment just waits a short time to ensure
    # notify(clean_run) runs after wait(cleanup_run)
    exp.data.cleanup = cleanup

    # setup all trial moments for this experiment
    experiment_context[] = Nullable(exp)
    fn()
    experiment_context[] = Nullable{Experiment}()

    # the last moment run cleans up the experiment
    enqueue!(exp.data.moments,final_moment(() -> cleanup()))
  catch e
    close(exp.win)
    gc_enable(true)
    rethrow(e)
  end
end

warmup_run(exp::Experiment{NullWindow}) = nothing
function warmup_run(exp::Experiment)
  # warm up JIT compilation
  warm_up = Experiment(null_window=true,hide_output=true)
  x = 0
  i = 0
  setup(warm_up) do
    addtrial(repeated(moment(t -> x += 1),10))
    addtrial(moment(t -> x += 1),
             moment(t -> x += 1) >> moment(t -> x += 1),
             moment(t -> x += 1))
    addtrial(loop=() -> (i+=1; i <= 3),
             moment(t -> x += 1),
             moment(t -> x += 1),
             moment(t -> x += 1))
  end
  run(warm_up)
end


function pause(exp,message,time,firstpause=true)
  exp.flags.running = false
  record(exp,"paused")
  if firstpause
    save_display(exp.win)
  end
  overlay = visual(colorant"gray",priority=Inf) + visual(message,priority=Inf)
  display(exp.win,overlay)
end

function unpause(exp,time)
  record(exp,"unpaused")
  exp.data.pause_mode = Running
  restore_display(exp.win)
  exp.data.last_bad_delta = -1.0
  exp.data.last_good_delta = -1.0
  exp.flags.running = true
  process_event(exp,EndPauseEvent(time))
end

const Running = 0
const ToExit = 1
const Unfocused = 2
const Error = 3

function watch_pauses(exp,e)
  if exp.data.pause_mode == Running && iskeydown(e,key":escape:")
    pause(exp,"Exit? [Y for yes, or N for no]",time(e))
    exp.data.pause_mode = ToExit
  elseif exp.data.pause_mode == Running && isunfocused(e) && exp.flags.processing
    pause(exp,"Waiting for window focus...",time(e))
    exp.data.pause_mode = Unfocused
  elseif exp.data.pause_mode == ToExit && iskeydown(e,key"y")
    record(exp,"terminated")
    exp.data.cleanup()
  elseif exp.data.pause_mode == ToExit && iskeydown(e,key"n")
    unpause(exp,time(e))
  elseif exp.data.pause_mode == Unfocused && isfocused(e)
    if exp.flags.processing
      pause(exp,"Paused. [To exit hit Y, to resume hit N]",time(e),false)
      exp.data.pause_mode = ToExit
    else
      exp.data.pause_mode = Running
      exp.flags.running = true
    end
  end
end

process_event(exp::Experiment,event::QuitEvent) = exp.data.cleanup()
function process_event(exp::Experiment,event)
  if exp.flags.running
    exp.data.trial_watcher(event)
    process(exp,exp.data.moments,event)
    process(exp,exp.data.submoments,event)
  end
  if exp.flags.processing
    watch_pauses(exp,event)
  end
end

const last_delta_resolution = 1
function report_deltas(exp::Experiment)
  if !exp.info.hide_output
    if exp.data.last_bad_delta > 0
      err = exp.data.last_bad_delta
      warn("""

The latency of trial moments has exceeded desirable levels ($err seconds). This
normally occurs when the experiment first starts up, but if unacceptable levels
continue throughout the experiment, consider closing some programs on your
computer or running this program on a faster machine. Poor latency will also
occur when you pause the experiment, because moments will not occur during a
pause.

           """)
      record(exp,"bad_delta_latency($err)")
    end

    if exp.data.last_good_delta > 0
      err = exp.data.last_good_delta
      exp.data.last_good_delta = -1.0
      info("""

The latency of trial moments has fallen to an acceptable level ($err
seconds). It may fall further, but unless it exceedes a tolerable level, you
will not be notified. Note that this measure of latency only verifies that the
commands to generate stimuli occur when they should. Emprical verification of
stimulus timing requires that you monitor the output of your machine using light
sensors and microphones. You can use the scripts available in
$(Pkg.dir("Weber","test")) to test the timing of auditory and visual
stimuli presented with Weber.

           """)
      record(exp,"good_delta_latency($err)")
    end
  end
end

const sleep_resolution = 0.01
const sleep_amount = 0.005

"""
    run(experiment)

Runs an experiment. You must call `setup` first.
"""
function run(exp::Experiment)
  warmup_run(exp)
  # println("========================================")
  # println("Completed warmup run.")
  try
    focus(exp.win)

    experiment_context[] = Nullable(exp)
    exp.data.pause_mode = Running
    exp.flags.processing = true
    exp.flags.running = true

    start = time()
    tick = exp.data.last_time = last_input = last_delta = 0.0
    while exp.flags.processing
      # notify all moments about the new time
      if exp.flags.running
        process(exp,exp.data.moments,tick)
        process(exp,exp.data.submoments,tick)
      end

      # handle all events (handles pauses, and notifys moments)
      if tick - last_input > exp.info.input_resolution
        check_events(process_event,exp,tick)
        last_input = tick
      end

      # report on any irregularity in the timing of moments
      if exp.flags.running && tick - last_delta > last_delta_resolution
        report_deltas(exp)
        last_delta = tick
      end
      # calculate next moment
      nexts = map(next_moment_time,exp.data.submoments)
      push!(nexts,next_moment_time(exp.data.moments))
      next_moment = minimum(nexts)

      # refresh screen
      refresh_display(exp.win)

      # if after all this processing there's still plenty of time left
      # then sleep for a while. (pausing also sleeps the loop)
      tick = exp.data.last_time = time() - start
      if ((tick - last_delta) > sleep_resolution &&
          (tick - last_input) > sleep_resolution &&
          (tick - next_moment) > sleep_resolution) ||
          !exp.flags.running

        sleep(sleep_amount)
      end
    end
  finally
    close(exp.win)
    gc_enable(true)
    if !exp.info.hide_output
      info("Experiment terminated at offset $(exp.data.offset). You can ",
           "find the collected data in $(exp.info.file).")
    end
  end
  nothing
end

function process(exp::Experiment,queues::Array{MomentQueue},x)
  filter!(queues) do queue
    !isempty(process(exp,queue,x).data)
  end
end

function process(exp::Experiment,queue::MomentQueue,event::ExpEvent)
  skip_offsets(exp,queue)

  if !isempty(queue)
    moment = front(queue)
    handled = handle(exp,queue,moment,event)
    if handled
      # println("--------")
      # @show moment
      # @show time(event)
      # @show queue.last

      dequeue!(queue)
      if update_last(moment)
        queue.last = time(event)
      end
    end
  end

  queue
end

function check_timing(exp::Experiment,moment::Moment,
                      run_t::Float64,last::Float64)
  const res = exp.info.moment_resolution
  d = delta_t(moment)
  if 0.0 < d < Inf
    empirical_delta = run_t - last
    error = abs(empirical_delta - d)
    if error > res
      exp.data.last_bad_delta = error
      exp.data.last_good_delta = -1.0
    elseif exp.data.last_bad_delta > res
      exp.data.last_bad_delta = -1.0
      exp.data.last_good_delta = error
    end
  end
end

function process(exp::Experiment,queue::MomentQueue,t::Float64)
  skip_offsets(exp,queue)

  if !isempty(queue)
    start_time = time()
    moment = front(queue)
    event_time = delta_t(moment) + queue.last
    if event_time - t <= exp.info.moment_resolution
      offset = t - start_time
      run_time = offset + time()
      while event_time > run_time
        run_time = offset + time()
      end
      exp.data.last_time = run_time
      handled = handle(exp,queue,moment,run_time)
      check_timing(exp,moment,run_time,queue.last)
      if handled
        # println("--------")
        # @show event_time
        # @show run_time
        # @show moment
        # @show t
        # @show queue.last

        dequeue!(queue)
        if update_last(moment)
          queue.last = run_time
        end
      end
    end
  end

  queue
end
