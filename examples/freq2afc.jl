#!/usr/bin/env julia

using Weber

version = v"0.0.1"
sid,trial_skip =
  @read_args("Frequency Discrimination ($version).")

const ms = 1/1000
const st = 1/12
atten_dB = 30
n_trials = 60

isresponse(e) = iskeydown(e,key"p") || iskeydown(e,key"q")

standard = attenuate(ramp(tone(1000,0.1)),atten_dB)
function one_trial(adapter)
  first_lower = rand(Bool)
  early_resp = response(key"q" => "early_first_lower",
                        key"p" => "early_second_lower")
  resp = response(adapter,key"q" => "first_lower",key"p" => "second_lower",
                  correct=(first_lower ? "first_lower" : "second_lower"))

  signal() = attenuate(ramp(tone(1000*(1-delta(adapter)),0.1)),atten_dB)
  stimuli = first_lower? [signal,standard] : [standard,signal]

  [show_cross(),early_resp,
   moment(play,stimuli[1]),moment(0.9,play,stimuli[2]),
   moment(0.1 + 0.3,display,
          "Was the first [Q] or second sound [P] lower in pitch?"),
   resp,
   await_response(isresponse)]
end

exp = Experiment(sid = sid,condition = "example",version = version,
                 skip=trial_skip,standard=1000,
                 columns = [:delta,:correct,:kind])

setup(exp) do
  start = moment(record,"start")

  addbreak(instruct("""

    On each trial, you will hear two beeps. Indicate which of the two beeps you
hear was lower in pitch. Hit 'Q' if the first beep was lower, and 'P' if the
second beep was lower.
"""))

  @addtrials let adapter = levitt_adapter(down=3,up=1,min_delta=0,max_delta=1,
                                          big=2,little=sqrt(2),mult=true)
    for trial in 1:n_trials
      addtrial(one_trial(adapter))
    end
  end
end

play(attenuate(ramp(tone(1000,1)),atten_dB))
run(exp)