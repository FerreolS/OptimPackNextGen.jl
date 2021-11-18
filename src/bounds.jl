#
# bounds.jl --
#
# Implement operations involving simple bound constraints.
#
# -----------------------------------------------------------------------------
#
# This file is part of OptimPackNextGen.jl which is licensed under the MIT
# "Expat" License.
#
# Copyright (C) 2015-2018, Éric Thiébaut.
# <https://github.com/emmt/OptimPackNextGen.jl>.
#

module SimpleBounds

export
    fastclamp,
    fastmax,
    fastmin,
    get_free_variables!,
    get_free_variables,
    project_direction!,
    project_gradient!,
    project_variables!,
    step_limits

using ArrayTools
using Base: @propagate_inbounds

"""
    fastmin(x, y)

yields the least of `x` and `y` if neither `x` nor `y` are NaNs, or `x`
otherwise.

Calling `fastmin(x,y)` is faster than `min(x,y)` but the latter propagates
NaNs (i.e., `min(x,y)` yields NaN if any of `x` or `y` is a NaN).

"""
fastmin(x::T, y::T) where {T<:Real} = (x > y ? y : x)

"""
    fastmax(x, y)

yields the greatest of `x` and `y` if neither `x` nor `y` are NaNs, or `x`
otherwise.

Calling `fastmax(x,y)` is faster than `max(x,y)` but the latter propagates
NaNs (i.e., `max(x,y)` yields NaN if any of `x` or `y` is a NaN).

"""
fastmax(x::T, y::T) where {T<:Real} = (x < y ? y : x)

"""
    fastclamp(x, lo, hi)

yields `x` subject to simple bound constraints.  That is, returns `x` if
`lo ≤ x ≤ hi`, `lo` if 'x < lo' and `hi` if `x > hi`.  This method is
similar to `clamp` except that bounds may be `nothing` to indicate that
there is no limit for the corresponding bound and that NaNs are not
treated specially.

"""
fastclamp(x::T, lo::T, hi::T) where {T<:Real} = fastmax(fastmin(x, hi), lo)
fastclamp(x::T, ::Nothing, hi::T) where {T<:Real} = fastmin(x, hi)
fastclamp(x::T, lo::T, ::Nothing) where {T<:Real} = fastmax(x, lo)

"""
    fastclamp(x, lo, hi, i)

yields `i`-th variable `x[i]` subject to simple bound constraints as
specified by `lo` and `hi`.

"""
@inline @propagate_inbounds fastclamp(x::AbstractArray, lo, hi, i) =
    fastclamp(x[i], bound_value(lo, i), bound_value(hi, i))

"""
    bound_value(b, i)

yields the bound value at index `i` for bounds `b`.

"""
bound_value(b::Nothing, i) = b
bound_value(b::Real, i) = b
@inline @propagate_inbounds bound_value(b::AbstractArray, i) = b[i]

"""
    SimpleBound{T,N}

is the union of types acceptable as simple bound for variables that are
`N`-dimensional arrays with element type `T`.

"""
const SimpleBound{T<:AbstractFloat,N} = Union{Nothing,Real,AbstractArray{T,N}}

"""
    lower_bound(T, x)

converts `x` to a proper lower bound for variables with element type `T`.  The
result is either a scalar of type `T` or an array with element type `T`.

"""
lower_bound(::Type{T}, ::Nothing) where {T<:AbstractFloat} = typemin(T)
lower_bound(::Type{T}, x::T) where {T<:AbstractFloat} = x
lower_bound(::Type{T}, x::Real) where {T<:AbstractFloat} = convert(T, x)::T
lower_bound(::Type{T}, x::AbstractArray{T,N}) where {T<:AbstractFloat,N} = x

"""
    upper_bound(T, x)

converts `x` to a proper upper bound for variables with element type `T`.  The
result is either a scalar of type `T` or an array with element type `T`.

"""
upper_bound(::Type{T}, ::Nothing) where {T<:AbstractFloat} = typemax(T)
upper_bound(::Type{T}, x::T) where {T<:AbstractFloat} = x
upper_bound(::Type{T}, x::Real) where {T<:AbstractFloat} =
    convert(T, x)::T
upper_bound(::Type{T}, x::AbstractArray{T,N}) where {T<:AbstractFloat,N} = x

#-------------------------------------------------------------------------------
# PROJECTING VARIABLES

"""
    project_variables!(dst, src, lo, hi) -> dst

overwrites destination `dst` the projection of the source variables `src` in the
box whose lower bound is `lo` and upper bound is `hi`.  The destination `dst`
is returned.

This is the same as `dst = clamp.(src, lo, hi)` except that the result is
preallocated and that the operation is *much* faster (by a factor of 2-3).

"""
function project_variables!(dst::AbstractArray{T,N},
                            src::AbstractArray{T,N},
                            lo::SimpleBound{T,N},
                            hi::SimpleBound{T,N}) where {T<:AbstractFloat,N}
    project_variables!(dst, src,
                       lower_bound(T, lo),
                       upper_bound(T, hi))
end

function project_variables!(dst::AbstractArray{T,N},
                            src::AbstractArray{T,N},
                            lo::T,
                            hi::T) where {T<:AbstractFloat,N}
    I = all_indices(dst, src)
    bounded_below = (lo > typemin(T))
    bounded_above = (hi < typemax(T))
    if bounded_below && bounded_above
        @inbounds @simd for i in I
            dst[i] = fastclamp(src[i], lo, hi)
        end
    elseif bounded_below
        @inbounds @simd for i in I
            dst[i] = fastclamp(src[i], lo, nothing)
        end
    elseif bounded_above
        @inbounds @simd for i in I
            dst[i] = fastclamp(src[i], nothing, hi)
        end
    elseif dst !== src
        vcopy!(dst, src)
    end
    return dst
end

function project_variables!(dst::AbstractArray{T,N},
                            src::AbstractArray{T,N},
                            lo::AbstractArray{T,N},
                            hi::T) where {T<:AbstractFloat,N}
    I = all_indices(dst, src, lo)
    if hi < typemax(T)
        @inbounds @simd for i in I
            dst[i] = fastclamp(src[i], lo[i], hi)
        end
    else
        @inbounds @simd for i in I
            dst[i] = fastclamp(src[i], lo[i], nothing)
        end
    end
    return dst
end

function project_variables!(dst::AbstractArray{T,N},
                            src::AbstractArray{T,N},
                            lo::T,
                            hi::AbstractArray{T,N}) where {T<:AbstractFloat,N}
    I = all_indices(dst, src, hi)
    if lo > typemin(T)
        @inbounds @simd for i in I
            dst[i] = fastclamp(src[i], lo, hi[i])
        end
    else
        @inbounds @simd for i in I
            dst[i] = fastclamp(src[i], nothing, hi[i])
        end
    end
    return dst
end

function project_variables!(dst::AbstractArray{T,N},
                            src::AbstractArray{T,N},
                            lo::AbstractArray{T,N},
                            hi::AbstractArray{T,N}) where {T<:AbstractFloat,N}
    @inbounds  @simd for i in all_indices(dst, src, lo, hi)
        dst[i] = fastclamp(src[i], lo[i], hi[i])
    end
    return dst
end

#------------------------------------------------------------------------------
# PROJECTING DIRECTION

# Orientation is indicated by a singleton.
abstract type Orientation end
struct Forward  <: Orientation; end
struct Backward <: Orientation; end

const FORWARD = Forward()
const BACKWARD = Backward()

Base.convert(::Type{Orientation}, ::Union{Forward,Type{Forward}}) = FORWARD
Base.convert(::Type{Orientation}, ::Union{Backward,Type{Backward}}) = BACKWARD
Base.convert(::Type{Orientation}, s::Real) = (s > 0 ? FORWARD :
                                              s < 0 ? BACKWARD :
                                              error("invalid orientation"))
Base.sign(::Union{Forward,Type{Forward}}) = +1
Base.sign(::Union{Backward,Type{Backward}}) = -1

Orientation(x) = convert(Orientation, x)
orientation(T::DataType, x) = Orientation(x) === FORWARD ? +one(T) : -one(T)

@inline projdir(x::T, lo::T, hi::T, ::Forward, d::T) where {T<:AbstractFloat} =
    (d > zero(T) ? x < hi : x > lo) ? d : zero(T)

@inline projdir(x::T, lo::T, hi::T, ::Backward, d::T) where {T<:AbstractFloat} =
    (d < zero(T) ? x < hi : x > lo) ? d : zero(T)

@inline projdir(x::T, ::Nothing, hi::T, ::Forward, d::T) where {T<:AbstractFloat} =
    (d < zero(T) || x < hi) ? d : zero(T)

@inline projdir(x::T, ::Nothing, hi::T, ::Backward, d::T) where {T<:AbstractFloat} =
    (d > zero(T) || x < hi) ? d : zero(T)

@inline projdir(x::T, lo::T, ::Nothing, ::Forward, d::T) where {T<:AbstractFloat} =
    (d > zero(T) || x > lo) ? d : zero(T)

@inline projdir(x::T, lo::T, ::Nothing, ::Backward, d::T) where {T<:AbstractFloat} =
    (d < zero(T) || x > lo) ? d : zero(T)

function project_gradient!(dst::AbstractArray{T,N},
                           x::AbstractArray{T,N},
                           lo::SimpleBound{T,N},
                           hi::SimpleBound{T,N},
                           d::AbstractArray{T,N}) where {T<:AbstractFloat,N}
    project_direction!(dst, x, lo, hi, BACKWARD, d)
end

function project_direction!(dst::AbstractArray{T,N},
                            x::AbstractArray{T,N},
                            lo::SimpleBound{T,N},
                            hi::SimpleBound{T,N},
                            orient,
                            d::AbstractArray{T,N}) where {T<:AbstractFloat,N}
    project_direction!(dst, x,
                       lower_bound(T, lo),
                       upper_bound(T, hi), Orientation(orient), d)
end

function project_direction!(dst::AbstractArray{T,N},
                            x::AbstractArray{T,N},
                            lo::T,
                            hi::T,
                            o::Orientation,
                            d::AbstractArray{T,N}) where {T<:AbstractFloat,N}
    I = all_indices(dst, x, d)
    lo ≤ hi || argument_error("invalid bounds") # this also checks for NaN
    bounded_above = (hi < typemax(T))
    bounded_below = (lo > typemin(T))
    if bounded_below && bounded_above
        @inbounds @simd for i in I
            dst[i] = projdir(x[i], lo, hi, o, d[i])
        end
    elseif bounded_below
        @inbounds @simd for i in I
            dst[i] = projdir(x[i], lo, nothing, o, d[i])
        end
    elseif bounded_above
        @inbounds @simd for i in I
            dst[i] = projdir(x[i], nothing, hi, o, d[i])
        end
    elseif dst !== d
        vcopy!(dst, d)
    end
    return dst
end

function project_direction!(dst::AbstractArray{T,N},
                            x::AbstractArray{T,N},
                            lo::AbstractArray{T,N},
                            hi::T,
                            o::Orientation,
                            d::AbstractArray{T,N}) where {T<:AbstractFloat,N}
    I = all_indices(dst, x, d, lo)
    if hi < typemax(T)
        @inbounds @simd for i in I
            dst[i] = projdir(x[i], lo[i], hi, o, d[i])
        end
    else
        @inbounds @simd for i in I
            dst[i] = projdir(x[i], lo[i], nothing, o, d[i])
        end
    end
    return dst
end

function project_direction!(dst::AbstractArray{T,N},
                            x::AbstractArray{T,N},
                            lo::T,
                            hi::AbstractArray{T,N},
                            o::Orientation,
                            d::AbstractArray{T,N}) where {T<:AbstractFloat,N}
    I = all_indices(dst, x, d, hi)
    if lo > typemin(T)
        @inbounds @simd for i in I
            dst[i] = projdir(x[i], lo, hi[i], o, d[i])
        end
    else
        @inbounds @simd for i in I
            dst[i] = projdir(x[i], nothing, hi[i], o, d[i])
        end
    end
    return dst
end

function project_direction!(dst::AbstractArray{T,N},
                            x::AbstractArray{T,N},
                            lo::AbstractArray{T,N},
                            hi::AbstractArray{T,N},
                            o::Orientation,
                            d::AbstractArray{T,N}) where {T<:AbstractFloat,N}
    I = all_indices(dst, x, d, lo, hi)
    @inbounds @simd for i in I
        dst[i] = projdir(x[i], lo[i], hi[i], o, d[i])
    end
    return dst
end

#------------------------------------------------------------------------------
# COMPUTING STEP LIMITS

"""
### Compute step limits for line search

When there are separable bound constraints on the variables, the step `smin` to
the closest not yet reached bound and the step `smax` to the farthest bound are
computed by the call:

    (smin, smax) = step_limits(x, lo, hi, s, d)

where `lo` is the lower bound, `hi` is the upper bound, `x` are the current
variables and `sign(s)*d` is the search direction.

In orther words, `smin` is the smallest step which will bring at least one more
variable "out of bounds" and `smax` is the smallest step which will bring all
variables "out of bounds".  As a consequence, `0 < smin` and `0 ≤ smax`.

"""
function step_limits(x::AbstractArray{T,N},
                     lo::SimpleBound{T,N},
                     hi::SimpleBound{T,N},
                     orient,
                     d::AbstractArray{T,N}) where {T<:AbstractFloat,N}
    return _step_limits(x,
                        lower_bound(T, lo),
                        upper_bound(T, hi),
                        orientation(T, orient), d)
end

# Private version.  Used to reduce the number of compiled versions and to
# ensure that s = ±1.
function _step_limits(x::AbstractArray{T,N},
                      lo::T,
                      hi::T,
                      s::T,
                      d::AbstractArray{T,N}) where {T<:AbstractFloat,N}
    I = all_indices(x, d)
    lo ≤ hi || argument_error("invalid bounds") # this also checks for NaN
    ZERO = zero(T)
    INFINITY = typemax(T)
    bounded_below = (lo > -INFINITY)
    bounded_above = (hi < +INFINITY)
    smin = INFINITY
    @inbounds begin
        if bounded_below && bounded_above
            smax = ZERO
            @simd for i in I
                p = s*d[i]
                if p != ZERO
                    a = (p > ZERO ? hi - x[i] : lo - x[i])/p
                    if ZERO < a < smin
                        smin = a
                    end
                    if a > smax
                        smax = a
                    end
                end
            end
        elseif bounded_below
            smax = ZERO
            @simd for i in I
                p = s*d[i]
                if p > ZERO
                    smax = INFINITY
                elseif p < ZERO
                    a = (lo - x[i])/p
                    if ZERO < a < smin
                        smin = a
                    end
                    if a > smax
                        smax = a
                    end
                end
            end
        elseif bounded_above
            smax = ZERO
            @simd for i in I
                p = s*d[i]
                if p > ZERO
                    a = (hi - x[i])/p
                    if ZERO < a < smin
                        smin = a
                    end
                    if a > smax
                        smax = a
                    end
                elseif p < ZERO
                    smax = INFINITY
                end
            end
        else
            smax = INFINITY
        end
    end
    return (smin, smax)
end

function _step_limits(x::AbstractArray{T,N},
                      lo::AbstractArray{T,N},
                      hi::T,
                      s::T,
                      d::AbstractArray{T,N}) where {T<:AbstractFloat,N}
    I = all_indices(x, d, lo)
    ZERO = zero(T)
    INFINITY = typemax(T)
    bounded_above = (hi < +INFINITY)
    smin = INFINITY
    smax = ZERO
    @inbounds begin
        if bounded_above
            @simd for i in I
                p = s*d[i]
                if p != ZERO
                    a = (p > ZERO ? hi - x[i] : lo[i] - x[i])/p
                    if ZERO < a < smin
                        smin = a
                    end
                    if a > smax
                        smax = a
                    end
                end
            end
        else
            @simd for i in I
                p = s*d[i]
                if p > ZERO
                    smax = INFINITY
                elseif p < ZERO
                    a = (lo[i] - x[i])/p
                    if ZERO < a < smin
                        smin = a
                    end
                    if a > smax
                        smax = a
                    end
                end
            end
        end
    end
    return (smin, smax)
end

function step_limits(x::AbstractArray{T,N},
                     lo::T,
                     hi::AbstractArray{T,N},
                     s::T,
                     d::AbstractArray{T,N}) where {T<:AbstractFloat,N}
    I = all_indices(x, d, hi)
    ZERO = zero(T)
    INFINITY = typemax(T)
    bounded_below = (lo > -INFINITY)
    smin = INFINITY
    smax = ZERO
    @inbounds begin
        if bounded_below
            @simd for i in I
                p = s*d[i]
                if p != ZERO
                    a = (p > ZERO ? hi[i] - x[i] : lo - x[i])/p
                    if ZERO < a < smin
                        smin = a
                    end
                    if a > smax
                        smax = a
                    end
                end
            end
        else
            @simd for i in I
                p = s*d[i]
                if p > ZERO
                    a = (hi[i] - x[i])/p
                    if ZERO < a < smin
                        smin = a
                    end
                    if a > smax
                        smax = a
                    end
                elseif p < ZERO
                    smax = INFINITY
                end
            end
        end
    end
    return (smin, smax)
end

function _step_limits(x::AbstractArray{T,N},
                      lo::AbstractArray{T,N},
                      hi::AbstractArray{T,N},
                      s::T,
                      d::AbstractArray{T,N}) where {T<:AbstractFloat,N}
    @assert size(x) == size(lo) == size(hi) == size(d)
    ZERO = zero(T)
    smin = typemax(T)
    smax = ZERO
    @inbounds begin
        @simd for i in eachindex(x, lo, hi, d)
            p = s*d[i]
            if p != ZERO
                # Step length to reach the upper/lower bound:
                a = (p > ZERO ? hi[i] - x[i] : lo[i] - x[i])/p
                if ZERO < a < smin
                    smin = a
                end
                if a > smax
                    smax = a
                end
            end
        end
    end
    return (smin, smax)
end

#------------------------------------------------------------------------------
# GETTING FREE VARIABLES

@inline may_move(x::T, lo::T, ::Nothing, ::Forward, d::T) where {T<:AbstractFloat} =
    d > zero(T) || (d != zero(T) && x > lo)

@inline may_move(x::T, lo::T, ::Nothing, ::Backward, d::T) where {T<:AbstractFloat} =
    d < zero(T) || (d != zero(T) && x > lo)

@inline may_move(x::T, ::Nothing, hi::T, ::Forward, d::T) where {T<:AbstractFloat} =
    d < zero(T) || (d != zero(T) && x < hi)

@inline may_move(x::T, ::Nothing, hi::T, ::Backward, d::T) where {T<:AbstractFloat} =
    d > zero(T) || (d != zero(T) && x < hi)

@inline may_move(x::T, lo::T, hi::T, ::Forward, d::T) where {T<:AbstractFloat} =
    d != zero(T) && (d < zero(T) ? x > lo : x < hi)

@inline may_move(x::T, lo::T, hi::T, ::Backward, d::T) where {T<:AbstractFloat} =
    d != zero(T) && (d > zero(T) ? x > lo : x < hi)

"""
## Get free variables when following a direction

    sel = get_free_variables(x, lo, hi, orient, d)

yields the list of components of the variables `x` which are allowed to vary
along the search direction `sign(orient)*d` under box constraints with `lo` and
`hi` the lower and upper bounds.

If the projected gradient `gp` of the objective function is available, the free
variables can be obtained by:

    sel = get_free_variables(gp)

where the projected gradient `gp` has been computed as:

    project_direction!(gp, x, lo, hi, -1, g)

with `g` the gradient of the objective function at `x`.

There are in-place versions:

    get_free_variables!(sel, x, lo, hi, orient, d) -> sel
    get_free_variables!(sel, gp)

"""
function get_free_variables(gp::DenseArray{T,N}) where {T<:AbstractFloat,N}
    get_free_variables!(resizable_vector(Int, length(gp)), gp)
end

function get_free_variables(x::DenseArray{T,N},
                            lo::Union{Real,DenseArray{T,N}},
                            hi::Union{Real,DenseArray{T,N}},
                            orient,
                            d::DenseArray{T,N}) where {T<:AbstractFloat,N}
    get_free_variables!(resizable_vector(Int, length(x)),
                        x, lo, hi, orient, d)
end

"""
    get_free_variables!(sel, x, lo, hi, orient, d) -> sel
    get_free_variables!(sel, gp) -> sel

are in-place versions of respectively:

    get_free_variables(x, lo, hi, orient, d) -> sel
    get_free_variables(gp) -> sel

Argument `sel` is overwritten with the result and resized as needed.

"""
function get_free_variables!(sel::Vector{Int},
                             gp::DenseArray{T,N}) where {T<:AbstractFloat,N}
    ZERO = zero(T)
    n = length(gp)
    resize!(sel, n)
    j = 0
    @inbounds @simd for i in 1:n
        if gp[i] != ZERO
            j += 1
            sel[j] = i
        end
    end
    return (j == n ? sel : resize!(sel, j))
end

function get_free_variables!(sel::Vector{Int},
                             x::DenseArray{T,N},
                             lo::Real,
                             hi::Real,
                             orient,
                             d::DenseArray{T,N}) where {T<:AbstractFloat,N}
    get_free_variables!(sel, x,
                        lower_bound(T, lo),
                        upper_bound(T, hi),
                        Orientation(orient), d)
end

function get_free_variables!(sel::Vector{Int},
                             x::DenseArray{T,N},
                             lo::T,
                             hi::T,
                             o::Orientation,
                             d::DenseArray{T,N}) where {T<:AbstractFloat,N}
    I = all_indices(x, d)
    lo ≤ hi || argument_error("invalid bounds") # this also checks for NaN
    bounded_below = (lo > typemin(T))
    bounded_above = (hi < typemax(T))
    n = length(x)
    resize!(sel, n)
    j = 0
    if bounded_below && bounded_above
        @inbounds @simd for i in I
            if may_move(x[i], lo, hi, o, d[i])
                j += 1
                sel[j] = i
            end
        end
    elseif bounded_below
        @inbounds @simd for i in I
            if may_move(x[i], lo, nothing, o, d[i])
                j += 1
                sel[j] = i
            end
        end
    elseif bounded_above
        @inbounds @simd for i in I
            if may_move(x[i], nothing, hi, o, d[i])
                j += 1
                sel[j] = i
            end
        end
    else
        @inbounds @simd for i in I
            sel[i] = i
        end
        j = n
    end
    return (j == n ? sel : resize!(sel, j))
end

function get_free_variables!(sel::Vector{Int},
                             x::DenseArray{T,N},
                             lo::DenseArray{T,N},
                             hi::T,
                             o::Orientation,
                             d::DenseArray{T,N}) where {T<:AbstractFloat,N}
    I = all_indices(x, d, lo)
    n = length(x)
    resize!(sel, n)
    j = 0
    if hi < typemax(T)
        @inbounds @simd for i in I
            if may_move(x[i], lo[i], hi, o, d[i])
                j += 1
                sel[j] = i
            end
        end
    else
        @inbounds @simd for i in I
            if may_move(x[i], lo[i], nothing, o, d[i])
                j += 1
                sel[j] = i
            end
        end
    end
    return (j == n ? sel : resize!(sel, j))
end

function get_free_variables!(sel::Vector{Int},
                             x::DenseArray{T,N},
                             lo::T,
                             hi::DenseArray{T,N},
                             o::Orientation,
                             d::DenseArray{T,N}) where {T<:AbstractFloat,N}
    I = all_indices(x, d, hi)
    n = length(x)
    resize!(sel, n)
    j = 0
    if lo > typemin(T)
        @inbounds @simd for i in I
            if may_move(x[i], lo, hi[i], o, d[i])
                j += 1
                    sel[j] = i
            end
        end
    else
        @inbounds @simd for i in I
            if may_move(x[i], nothing, hi[i], o, d[i])
                j += 1
                sel[j] = i
            end
        end
    end
    return (j == n ? sel : resize!(sel, j))
end

function get_free_variables!(sel::Vector{Int},
                             x::DenseArray{T,N},
                             lo::DenseArray{T,N},
                             hi::DenseArray{T,N},
                             o::Orientation,
                             d::DenseArray{T,N}) where {T<:AbstractFloat,N}
    I = all_indices(x, d, lo, hi)
    n = length(x)
    resize!(sel, n)
    j = 0
    @inbounds @simd for i in I
        if may_move(x[i], lo[i], hi[i], o, d[i])
            j += 1
            sel[j] = i
        end
    end
    return (j == n ? sel : resize!(sel, j))
end

function resizable_vector(::Type{T}, n::Integer) where {T}
    vec = Vector{T}(undef, n)
    sizehint!(vec, n)
    return vec
end

#------------------------------------------------------------------------------

end # module
