using Base.Iterators: repeated, countfrom, flatten, take, peel
using Base.Broadcast: Broadcasted, BroadcastStyle, Style, DefaultArrayStyle, ArrayConflict
using Base.Broadcast: materialize, materialize!, instantiate, preprocess, broadcast_axes, _broadcast_getindex

### An operator which does not expect to be called.

"""
  `unspecifiedop(a, b)` is a reduction operator which does not expect to be called. It startles easily.
"""
unspecifiedop(a, b) = throw(ArgumentError("unspecified reduction operator"))

### Lazy-wrapper for swizzling

# `Swizzled` wraps the argument to `swizzle(A, mask, op=unspecifiedop)`. A
# statement like
#    y = Swizzler((1,), +).(x .* (Swizzler((2, 1)).x .+ 1))
# will result in code that is essentially
#    y = copy(Swizzled(Broadcasted(*, Swizzled(x, (2, 1)), Broadcasted(+, x, 1)), (1,), +))
# `swizzle!` results in `copyto!(dest, Swizzled(...))`.
# `mask` is an iterator of nonnegative integers specifying where dimensions of
# the wrapped `A` will appear in the output array. Each dimension of `A` may be
# used at most once in `mask`, but `pass` is a special value that may be used
# to specify that a dimension is expected to be dropped. Uniqueness of integers
# in `mask` cannot be checked, since `mask` may be infinitely long. If `mask`
# is not long enough, remaining dimensions are passped. `mask` is lifted into
# the type domain

struct Swizzled{Style<:Union{Nothing,BroadcastStyle}, Axes, imask, Arg, mask, Op}
    arg::Arg
    op::Op
    axes::Axes
    #TODO enforce inv swizzle/other properties?
end

_mask(::Type{<:Swizzled{<:Any, <:Any, <:Any, <:Any, mask}}) where {mask} = mask
_mask(sz::Swizzled) = _mask(typeof(sz))
_imask(::Type{<:Swizzled{<:Any, <:Any, imask}}) where {imask} = imask
_imask(sz::Swizzled) = _imask(typeof(sz))

#= TODO do we need this?
BroadcastStyle(::Type{<:Swizzled{Style}}) where {Style} = Style()
BroadcastStyle(::Type{<:Swizzled{S}}) where {S<:Union{Nothing,Unknown}} =
    throw(ArgumentError("Swizzled{Unknown} wrappers do not have a style assigned"))

argtype(::Type{Swizzled{<:Any,<:Any,<:Any,<:Any,Arg}}) where {Arg} = Arg
argtype(sz::Swizzled) = argtype(typeof(sz))
=#

Swizzled(arg, mask, op=unspecifiedop, axes=nothing, imask=nothing) =
    Swizzled{typeof(swizzle_style(BroadcastStyle(typeof(arg)), mask, op))}(arg, mask, op, axes, imask)
Swizzled{Style}(arg, mask, op=unspecifiedop, axes=nothing, imask=nothing) where {Style} =
    Swizzled{Style, typeof(axes), imask, typeof(arg), mask, Core.Typeof(op)}(arg, op, axes)

Base.convert(::Type{Swizzled{Style}}, sz::Swizzled) where {Style} =
    Swizzled{Style}(sz.arg, _mask(sz), sz.op, sz.axes, _imask(sz))

function Base.show(io::IO, sz::Swizzled{Style}) where {Style}
    print(io, Swizzled)
    # Only show the style parameter if we have a set of axes — representing an instantiated
    # "outermost" Swizzled. The styles of nested Broadcasteds represent an intermediate
    # computation that is not relevant for dispatch, confusing, and just extra line noise.
    sz.axes isa Tuple && print(io, '{', Style, '}')
    print(io, '(', sz.arg, ", ", _mask(sz), ", ", sz.op, ')')
    nothing
end

## Allocating the output container
Base.similar(sz::Swizzled{DefaultArrayStyle}, ::Type{ElType}) where {ElType} =
    similar(Array{ElType}, axes(sz))
Base.similar(sz::Swizzled{DefaultArrayStyle}, ::Type{Bool}) =
    similar(BitArray, axes(sz))
# In cases of conflict we fall back on Array
Base.similar(sz::Swizzled{ArrayConflict}, ::Type{ElType}) where ElType =
    similar(Array{ElType}, axes(sz))
Base.similar(sz::Swizzled{ArrayConflict}, ::Type{Bool}) =
    similar(BitArray, axes(sz))

## Computing the result's axes. Most types probably won't need to specialize this.
instantiate_mask(sz::Swizzled) = _instantiate_mask(sz, _mask(sz))
_instantiate_mask(sz::Swizzled, mask::Tuple) = mask
_instantiate_mask(sz::Swizzled, mask) = (take(mask, length(broadcast_axes(sz.arg)))...,)

instantiate_imask(sz::Swizzled) = _instantiate_imask(sz, _imask(sz), _mask(sz))
_instantiate_imask(sz::Swizzled, imask::Tuple, mask) = imask
_instantiate_imask(sz::Swizzled, imask::Nothing, mask::Tuple) = setindexinto((repeated(pass, max(0, maximum(mask)))...,), 1:length(mask), mask)
_instantiate_imask(sz::Swizzled, imask::Nothing, mask) = _instantiate_imask(sz, imask, _instantiate_mask(sz, mask))

@inline Base.axes(sz::Swizzled) = _axes(sz, sz.axes, _imask(sz))
_axes(sz::Swizzled, axes::Tuple, imask) = axes
_axes(sz::Swizzled, axes::Nothing, imask::Tuple) = getindexinto((repeated(Base.OneTo(1), length(imask))...,), broadcast_axes(sz.arg), imask)
_axes(sz::Swizzled, axes::Nothing, imask::Nothing) = _axes(sz, nothing, instantiate_imask(sz))

@inline Base.eachindex(sz::Swizzled) = _eachindex(axes(sz))
_eachindex(t::Tuple{Any}) = t[1]
_eachindex(t::Tuple) = CartesianIndices(t)

Base.ndims(::Swizzled{<:Any,<:Tuple{Vararg{<:Any}}}) where {N} = N
Base.ndims(::Type{<:Swizzled{<:Any,<:Tuple{Vararg{<:Any}}}}) where {N} = N

Base.length(sz::Swizzled) = prod(map(length, axes(sz)))

function Base.iterate(sz::Swizzled)
    iter = eachindex(sz)
    iterate(sz, (iter,))
end
Base.@propagate_inbounds function Base.iterate(sz::Swizzled, s)
    y = iterate(s...)
    y === nothing && return nothing
    i, newstate = y
    return (sz[i], (s[1], newstate))
end

Base.IteratorSize(::Type{<:Swizzled{<:Any,<:NTuple{N}}}) where {N} = Base.HasShape{N}()
Base.IteratorEltype(::Type{<:Swizzled}) = Base.EltypeUnknown()

## Instantiation fills in the "missing" fields in Swizzled.

"""
    Broadcast.instantiate(sz::Swizzled)
Construct and check the imask, mask, and axes and for the lazy Swizzle object `sz`.
Custom [`BroadcastStyle`](@ref)s may override this default in cases where it is fast and easy
to compute and verify the resulting `axes` on-demand, leaving the `axis` field
of the `Swizzled` object empty (populated with [`nothing`](@ref)).
"""
@inline function Base.Broadcast.instantiate(sz::Swizzled{Style}) where {Style}
    if sz.axes isa Nothing || _imask(sz) isa Nothing || !(_mask(sz) isa Tuple)
        mask = instantiate_mask(sz)
        imask = _instantiate_imask(sz, _imask(sz), mask)
        axes = _axes(sz, sz.axes, imask)
        return Swizzled{Style}(sz.arg, mask, sz.op, axes, imask)
    else
        check_swizzle(sz)
        return sz
    end
end

function check_swizzle(sz)
    #= FIXME
    @assert mask(sz) isa Tuple{Vararg{<:Union{Int, Pass}}}
    @assert _imask(sz) isa Tuple{Vararg{<:Union{Int, Pass}}}
    @assert length(mask) == length(axes(sz.arg))
    @assert length(imask) == length(sz.axes)
    @assert max(0, maximum(mask)) == length(imask)
    @assert max(0, maximum(imask)) == length(mask)
    @assert all(map(d -> d isa Pass || 1 <= d, mask))
    @assert any(map(d -> d isa Int && d == maximum(mask)))
    @assert (minimum(mask) isa Int && minimum(mask) >= 1) || minimum(mask) isa Pass
    @assert (maximum(mask) isa Int && maximum(mask) == length(imask)) || (maximum(gmask) isa Pass && length(imask) == 0)
    @assert all(map(((i, j),) -> m isa Pass || imask[m] == i, enumerate(gmask)))
    @assert all(map(((i, j),) -> m isa Pass || gmask[m] == i, enumerate(imask)))
    @assert all(map(((i, j),) -> (j isa Pass && axes[i] == 1:1) || axes[i] == argaxes[j], enumerate(imask)))
    =#
end

## Flattening swizzles is difficult and people shouldn't flatten broadcasts anyway. Harumph.

### Objects with customized swizzling behavior should define a corresponding BroadcastStyle

"""
  `swizzle_style(style, mask, op=unspecifiedop)`
Broadcast styles are used to determine behavior of objects under swizzling.  To
customize the swizzling behavior of a type, one can first define an appropriate
Broadcast style for the the type, then declare how the broadcast style should
behave under broadcasting after the swizzle by overriding the
`swizzle_style` method.
"""
swizzle_style

swizzle_style(::Style{Tuple}, mask, op) = first(mask) == 1 ? Style{Tuple}() : DefaultArrayStyle(Val(first(mask)))
swizzle_style(style::A, mask, op) where {N, A <: Broadcast.AbstractArrayStyle{N}} = A(Val(maximum(take(mask, N))))
swizzle_style(style::Broadcast.AbstractArrayStyle{Any}, mask, op) = style
swizzle_style(::BroadcastStyle, mask, op) = Broadcast.Unknown()
swizzle_style(::ArrayConflict, mask, op) = Broadcast.ArrayConflict() #FIXME

Broadcast.BroadcastStyle(::Type{<:Swizzled{Nothing, Axes, imask, Arg, mask, Op}}) where {Style, Axes, imask, Arg, mask, Op} = swizzle_style(BroadcastStyle(Arg), mask, Op)
Broadcast.BroadcastStyle(::Type{<:Swizzled{Style}}) where {Style} = Style()

@inline function Base.getindex(sz::Swizzled, I::Integer)
    #@boundscheck checkbounds(sz, I) FIXME
    inds = eachindex(getindexinto(axes(sz.arg), I, _mask(sz)))
    (i, inds) = peel(inds)
    res = @inbounds getindex(sz.arg, i)
    for i in inds
        res = sz.op(res, @inbounds getindex(sz.arg, i))
    end
    return res
end
@inline function Base.getindex(sz::Swizzled, I::CartesianIndex)
    #@boundscheck checkbounds(sz, I) FIXME
    inds = eachindex(getindexinto(axes(sz.arg), Tuple(I), instantiate_mask(sz)))
    (i, inds) = peel(inds)
    res = @inbounds getindex(sz.arg, i)
    for i in inds
        res = sz.op(res, @inbounds getindex(sz.arg, i))
    end
    return res
end
Base.@propagate_inbounds Base.getindex(sz::Swizzled, i1::Integer, i2::Integer, I::Integer...) = sz[CartesianIndex((i1, i2, I...))]
Base.@propagate_inbounds Base.getindex(sz::Swizzled) = sz[CartesianIndex(())]

#=
@inline Base.checkbounds(bc::Broadcasted, I::Union{Integer,CartesianIndex}) =
    Base.checkbounds_indices(Bool, axes(bc), (I,)) || Base.throw_boundserror(bc, (I,))
=# #TODO why would anyone need this?

Base.Broadcast.broadcastable(sz::Swizzled) = sz

## Swizzling core

"""
    swizzle(A, mask, op=unspecifiedop)
Create a new obect `B` such that the dimension `i` of `A` is mapped to
dimension `mask[i]` of `B`, operating on lazy broadcast expressions, arrays,
tuples, collections, [`Ref`](@ref)s and/or scalars `As`. If `mask[i]` is an
instance of the singleton type `Pass`, the dimension is reduced over using
`op`. `mask` may be any (possibly infinite) iterable over elements of type
`Int` and `Pass`. The integers in `mask` must be unique, and if `mask` is
not long enough, additional `pass` are added to the end.
The resulting container type is established by the following rules:
 - If all elements of `mask` are `Pass`, it returns an unwrapped scalar.
 - All other combinations of arguments default to returning an `Array`, but
   custom container types can define their own implementation rules to
   customize the result when they appear as an argument.
The swizzle operation is represented with a special lazy `Swizzled` type.
`swizzle` results in `copy(Swizzled(...))`.
The swizzle operation can use a special `Swizzler` type to take advantage of
the special broadcast syntax. A statement like:
   y = Swizzler((1,), +).(x .* (Swizzler((2, 1)).x .+ 1))
will result in code that is essentially:
   y = copy(Swizzled(Broadcasted(*, Swizzled(x, (2, 1)), Broadcasted(+, x, 1)), (1,), +))
If Swizzleds are mixed with Broadcasteds, the result is fused into one big for loop.
# Examples
```jldoctest
julia> A = [1, 2, 3, 4, 5]
5-element Array{Int64,1}:
 1
 2
 3
 4
 5
julia> B = [1 2; 3 4; 5 6; 7 8; 9 10]
5×2 Array{Int64,2}:
 1   2
 3   4
 5   6
 7   8
 9  10
julia> swizzle(B, (1,), +)
5×2 Array{Int64,2}:
 3
 7
 11
 15
 19
julia> swizzle(B, (), +)
55
julia> Swizzler((2,)).(parse.(Int, ["1", "2"]))
1x2-element Array{Int64,1}:
 1 2
"""
swizzle(A, mask, op=unspecifiedop) = materialize(Swizzled(A, mask, op))

"""
    swizzle!(A, mask, op=unspecifiedop)
Like [`swizzle`](@ref), but store the result of
`swizzle(A, mask, op)` in the `dest` array.
Note that `dest` is only used to store the result
`swizzle!` results in `copyto!(dest, Swizzled(...))`.
# Examples
```jldoctest
julia> A = [1.0; 0.0]; B = [0.0; 0.0];
julia> broadcast!(+, B, A, (0, -2.0));
julia> B
2-element Array{Float64,1}:
  1.0
 -2.0
julia> A
2-element Array{Float64,1}:
 1.0
 0.0
julia> broadcast!(+, A, A, (0, -2.0));
julia> A
2-element Array{Float64,1}:
  1.0
 -2.0
```
"""
swizzle!(dest, A, mask, op=unspecifiedop) = (materialize!(dest, Swizzled(A, mask, op)); dest)

@inline Base.Broadcast.materialize(sz::Swizzled) = copy(sz)

@inline Base.Broadcast.materialize!(dest, sz::Swizzled) = copyto!(dest, sz)



Base.copy(sz::Swizzled{Style}) where {Style} = copy(Swizzled{Nothing}(sz.arg, _mask(sz), sz.op, sz.axes, _imask(sz)))

Base.copyto!(dest, sz::Swizzled{Style}) where {Style} = copyto!(dest, Swizzled{Nothing}(sz.arg, _mask(sz), sz.op, sz.axes, _imask(sz)))

Base.copy(sz::Swizzled{Nothing}) = copy(instantiate(Broadcasted(identity, (sz,))))

Base.copyto!(dest, sz::Swizzled{Nothing}) = copyto(dest, instantiate(Broadcasted(identity, (sz,))))

Base.Broadcast.preprocess(dest, sz::Swizzled{Style}) where {Style} = instantiate(Swizzled{Style}(sz.arg, _mask(sz), sz.op, sz.axes, _imask(sz))) #TODO problem here too.

struct Swizzler
    mask
    op
end

Base.Broadcast.broadcasted(style::BroadcastStyle, szr::Swizzler, arg) = Swizzled(arg, szr.mask, szr.op) #Should use style here duh.


function Beam(arg, dims...)
    Swizzled(arg, flatten((dims, repeated(pass))), unspecifiedop)
end

function NoSum(dims::Int...)
    m = maximum((0, dims...))
    Swizzler(setindexinto((take(repeated(pass), m)...,), 1:length(dims), dims), +)
end

function Sum(dims::Int...)
    Reduce(dims, +)
end

function Reduce(dims, op)
    m = maximum((0, dims...))
    s = Set(dims)
    c = 1
    Swizzler(flatten((ntuple(d -> d in s ? pass : c += 1, m), countfrom(m - length(s) + 1))), op)
end



function Permute(perm::Int...)
    @assert isperm(perm)
    Swizzler(flattened(invperm(perm), count(length(perm) + 1)), unspecifiedop)
end