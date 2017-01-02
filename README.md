# Psychotask

[![Build Status](https://travis-ci.org/haberdashPI/Psychotask.jl.svg?branch=master)](https://travis-ci.org/haberdashPI/Psychotask.jl)

[![Coverage Status](https://coveralls.io/repos/haberdashPI/Psychotask.jl/badge.svg?branch=master&service=github)](https://coveralls.io/github/haberdashPI/Psychotask.jl?branch=master)

[![codecov.io](http://codecov.io/github/haberdashPI/Psychotask.jl/coverage.svg?branch=master)](http://codecov.io/github/haberdashPI/Psychotask.jl?branch=master)

# About

This package is a relatively recent effort to create a simple framework for
running psychology experiments that present stimuli and record responses in
real-time. It is similar in concept to the likes of Presentation or ePrime. It
currently runs on Windows and Mac OS X, and supports keyboard input or
Cendrus response-pad input.

It should be easy to port this to a unix system, I just don't have a
linux currently installed to test for proper installation of SDL2, and so I
haven't gotten around to this.

## Status

This is working for my own purposes, and I am running pilot experiments in it
now. It has not been throughly tested yet however, but will be as I finalize
those studies. Many of the individual functions are documented but there is
useful functionality that has not yet been documented, and there is no user
manual. Please feel free to use it, but use at your own risk.

# Installation

```julia
julia> Pkg.clone("https://github.com/haberdashPI/Psychotask.jl")
julia> Pkg.build("Psychotask")
```

# Roadmap

For the 0.2.0 release
- [ ] document object composition
- [ ] document moment composition
- [ ] document experiment construction
- [ ] create a basic user manual

- [ ] test responses to Cedrus XID devices (create example for reading buttons)
- [ ] allow resetting of Cedrus response timer
- [ ] debug (or remove) harmonic_complex
- [ ] define some tests to evaluate the documented effects of the trial timing functions.

- [ ] submit the package to METADATA.jl
- [ ] use the version number of Psychotask.jl indicated by Pkg

For the 0.3.0 release
- [ ] refine the user manual
- [ ] create 2AFC abstraction
- [ ] create examples to demonstrate all package features
- [ ] allow calls to Cedrus stim tracker??
- [ ] support linux (get BinDeps working for installation)

For the 0.4.0 release?
- [ ] port XID python code to julia (to minimize memory footprint)
- [ ] implement support for Compose.jl
- [ ] create an interface for playing mp4 videos.
