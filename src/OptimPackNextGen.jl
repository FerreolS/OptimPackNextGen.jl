#
# OptimPackNextGen.jl --
#
# Package for numerical optimization in Julia.
#
# -----------------------------------------------------------------------------
#
# This file is part of OptimPackNextGen.jl which is licensed under the MIT
# "Expat" License.
#
# Copyright (C) 2015-2017, Éric Thiébaut.
#

isdefined(Base, :__precompile__) && __precompile__(true)

module OptimPackNextGen

export
    fmin,
    fzero,
    nllsq,
    nllsq!,
    conjgrad,
    conjgrad!,
    vmlmb,
    vmlmb!,
    spg,
    spg!,
    getreason

doc"""
`Float` is the type of all floating point scalars, it is currently an alias to
`Cdouble` which is itself an alias to `Float64`.
"""
const Float = Cdouble

function getreason end

include("algebra.jl")
importall .Algebra

include("conjgrad.jl")

include("linesearches.jl")

include("quasinewton.jl")
importall .QuasiNewton

include("brent.jl")
import .Brent: fmin, fzero

include("powell.jl")

include("nllsq.jl")
using .NonLinearLeastSquares

include("bradi.jl")

include("step.jl")

include("spg.jl")
importall .SPG

end # module
