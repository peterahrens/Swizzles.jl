using Swizzles.Properties
using Swizzles.WrapperArrays
using Swizzles.ArrayifiedArrays
using Swizzles.GeneratedArrays
using Swizzles.ExtrudedArrays
using Swizzles.ValArrays
using Swizzles.NamedArrays
using Swizzles.ScalarArrays

using Base: checkbounds_indices, throw_boundserror, tail, dataids, unaliascopy, unalias
using Base.Iterators: reverse, repeated, countfrom, flatten, product, take, peel, EltypeUnknown
using Base.Broadcast: Broadcasted, BroadcastStyle, Style, DefaultArrayStyle, AbstractArrayStyle, Unknown, ArrayConflict
using Base.Broadcast: materialize, materialize!, instantiate, broadcastable, preprocess, _broadcast_getindex, combine_eltypes, broadcast_shape
using Base.FastMath: add_fast, mul_fast, min_fast, max_fast
using StaticArrays
using Base.Cartesian



struct SwizzledArray{T, N, Op, mask, Init<:AbstractArray, Arg<:AbstractArray} <: GeneratedArray{T, N}
    op::Op
    init::Init
    arg::Arg
    Base.@propagate_inbounds function SwizzledArray{T, N, Op, mask, Init, Arg}(op::Op, init::Init, arg::Arg) where {T, N, Op, mask, Init, Arg}
        @assert T isa Type
        @assert max(0, mask...) <= ndims(arg)
        @assert length(mask) == N
        #TODO assert mask is unique
        if op === nothing
            @boundscheck begin
                arg_keeps = keeps(arg)
                if any(imasktuple(d->kept(arg_keeps[d]), d->false, Val(mask), Val(ndims(arg))))
                    throw(DimensionMismatch("TODO"))
                end
            end
        end
        new(op, init, arg)
    end
end

@inline function SwizzledArray{T, N, Op, mask}(op::Op, init::Init, arg::Arg) where {T, N, Op, mask, Init, Arg}
    SwizzledArray{T, N, Op, mask, Init, Arg}(op, init, arg)
end

@inline function Base.convert(::Type{SwizzledArray{T}}, arr::SwizzledArray{S, N, Op, mask, Init, Arg}) where {T, S, N, Op, mask, Init, Arg}
    return SwizzledArray{T, N, Op, mask, Init, Arg}(arr.op, arr.init, arr.arg)
end

@inline function Properties.eltype_bound(arr::SwizzledArray)
    S = Properties.eltype_bound(arr.arg)
    if arr.op === nothing
        return S
    end
    T = Properties.eltype_bound(arr.init)
    T! = Union{T, Properties.return_type(arr.op, T, S)}
    if T! <: T
        return T!
    end
    arg_keeps = keeps(arr.arg)
    arr_mask = mask(arr)
    if all(imasktuple(d->arg_keeps[d] isa Extrude, d->true, Val(mask(arr)), Val(ndims(arr.arg))))
        return T!
    end
    T = T!
    T! = Union{T, Properties.return_type(arr.op, T, S)}
    if T! <: T
        return T!
    end
    return Any
end

@inline mask(::Type{<:SwizzledArray{<:Any, <:Any, <:Any, _mask}}) where {_mask} = _mask
@inline mask(::SwizzledArray{<:Any, <:Any, <:Any, _mask}) where {_mask} = _mask



function Base.show(io::IO, arr::SwizzledArray{T, N, Op, mask}) where {T, N, Op, mask}
    print(io, SwizzledArray)
    print(io, "{$T, $N, $Op, $mask}($(arr.op), $(arr.init), $(arr.arg))")
    nothing
end

Base.parent(arr::SwizzledArray) = arr.arg
Base.parent(::Type{<:SwizzledArray{T, N, Op, mask, Init, Arg}}) where {T, N, Op, mask, Init, Arg} = Arg
WrapperArrays.iswrapper(arr::SwizzledArray) = true
Base.@propagate_inbounds function WrapperArrays.adopt(arg::Arg, arr::SwizzledArray{T, N, Op, mask, Init}) where {T, N, Op, mask, Init, Arg}
    SwizzledArray{T, N, Op, mask, Init, Arg}(arr.op, arr.init, arg)
end

Base.dataids(arr::SwizzledArray) = (dataids(arr.op), dataids(arr.init), dataids(arr.arg))
function Base.unaliascopy(arr::SwizzledArray{T, N, Op, mask}) where {T, N, Op, mask}
    op = unaliascopy(arr.op)
    init = unaliascopy(arr.init)
    arg = unaliascopy(arr.arg)
    SwizzledArray{T, N, typeof(op), mask, typeof(init), typeof(arg)}(op, init, arg)
end
function Base.unalias(dst, arr::SwizzledArray{T, N, Op, mask}) where {T, N, Op, mask}
    op = unalias(dst, arr.op)
    init = unalias(dst, arr.init)
    arg = unalias(dst, arr.arg)
    SwizzledArray{T, N, typeof(op), mask, typeof(init), typeof(arg)}(op, init, arg)
end

@inline function Base.size(arr::SwizzledArray)
    arg_size = size(arr.arg)
    masktuple(d->1, d->arg_size[d], Val(mask(arr)))
end

@inline function Base.axes(arr::SwizzledArray)
    arg_axes = axes(arr.arg)
    masktuple(d->Base.OneTo(1), d->arg_axes[d], Val(mask(arr)))
end



Base.@propagate_inbounds function Base.convert(::Type{SwizzledArray}, src::SubArray{T, M, Arr, <:Tuple{Vararg{Any, N}}}) where {T, N, M, Op, Arr <: SwizzledArray{T, N, Op}}
    arr = parent(src)
    inds = Base.parentindices(src)
    arg = arr.arg
    init = arr.init
    init′ = SubArray(init, ntuple(n -> (Base.@_inline_meta; size(init, n) == 1 ? firstindex(init, n) : inds[n]), Val(ndims(init))))
    arg_axes = axes(arr.arg)
    inds′ = imasktuple(d->Base.Slice(arg_axes[d]), d->inds[d], Val(mask(arr)), Val(ndims(arr.arg)))
    arg′ = SubArray(arg, inds′)
    mask′ = remask(inds, inds′, mask(arr))
    return SwizzledArray{eltype(src), M, Op, mask′}(arr.op, init′, arg′)
end

@inline function remask(inds, inds′, mask::Tuple{})
    ()
end
@inline function remask(inds, inds′, mask)
    counts = _remask_counts((), inds′)
    _remask_mask(counts, inds, mask)
end
@inline function _remask_mask(counts, inds, mask)
    rest = _remask_mask(counts, Base.tail(inds), Base.tail(mask))
    if Base.index_dimsum(first(inds)) isa Tuple{}
        return rest
    elseif first(mask) === nil
        return (nil, rest...)
    else
        return (counts[first(mask)], rest...)
    end
end
@inline _remask_mask(counts, ::Tuple{}, ::Tuple{}) = ()
@inline function _remask_counts(firsts, inds′)
    firsts = (firsts..., first(inds′))
    return (length(Base.index_dimsum(firsts...)), _remask_counts(firsts, Base.tail(inds′))...)
end
@inline _remask_counts(counts, ::Tuple{}) = ()



Base.similar(::Broadcasted{DefaultArrayStyle{0}, <:Any, typeof(identity), <:Tuple{<:SwizzledArray{T}}}) where {T} = ScalarArray{T}()



Base.@propagate_inbounds function Base.copy(src::Broadcasted{DefaultArrayStyle{0}, <:Any, typeof(identity), <:Tuple{Arr}}) where {Arr <: SwizzledArray}
    arr = src.args[1]
    dst = similar(src)
    copyto!(dst, Broadcasted{DefaultArrayStyle{0}}(identity, (arr,)))
    return dst[]
end

Base.@propagate_inbounds function Base.copy(src::Broadcasted{DefaultArrayStyle{0}, <:Any, typeof(identity), <:Tuple{SubArray{T, <:Any, <:SwizzledArray{T, N}, <:Tuple{Vararg{Any, N}}}}}) where {T, N}
    return Base.copy(Broadcasted{DefaultArrayStyle{0}}(identity, (convert(SwizzledArray, src.args[1]),)))
end

for Identity = (typeof(identity), typeof(myidentity))
    for Style = (AbstractArrayStyle{0}, AbstractArrayStyle, DefaultArrayStyle, Style{Tuple})
        @eval begin
            Base.@propagate_inbounds function Base.copyto!(dst::AbstractArray, src::Broadcasted{<:$Style, <:Any, $Identity, <:Tuple{SubArray{T, <:Any, <:SwizzledArray{T, N}, <:Tuple{Vararg{Any, N}}}}}) where {T, N}
                #A view of a Swizzle can be computed as a swizzle of a view (hiding the
                #complexity of dropping view indices). Therefore, we convert first.
                return Base.copyto!(dst, convert(SwizzledArray, src.args[1]))
            end

            Base.@propagate_inbounds function Base.copyto!(dst::AbstractArray, src::Broadcasted{<:$Style, <:Any, $Identity, <:Tuple{SwizzledArray}})
                #This method gets called when the destination eltype is unsuitable for
                #accumulating the swizzle. Therefore, we should allocate a suitable
                #destination and then accumulate.
                arr = src.args[1]
                arr′ = copyto!(similar(arr), arr)
                @assert ndims(dst) == ndims(arr′)
                copyto!(dst, arr′)
            end

            Base.@propagate_inbounds function Base.copyto!(dst::AbstractArray{T, N}, src::Broadcasted{<:$Style, <:Any, $Identity, Tuple{Arr}}) where {T, N, Arr <: SwizzledArray{<:T, N}}
                arg = ArrayifiedArrays.preprocess(dst, src.args[1].arg)
                arr = adopt(arg, src.args[1])
                op = arr.op
                init = arr.init
                @boundscheck axes(dst) == axes(arr)
                @inbounds begin
                    index = swizzleindex(dst, arr)
                    drive = eachindex(arg, index)
                    if op === nothing
                        assign!(dst, index, arg, drive)
                    else
                        dst .= init
                        increment!(op, dst, index, arg, drive)
                    end
                end
                return dst
            end
        end
    end
end



is_nil_mask(mask) = mask == ntuple(n->nil, length(mask))
@generated function is_nil_mask(::Val{mask}) where {mask}
    return is_nil_mask(mask)
end

is_oneto_mask(mask) = mask == 1:length(mask)
@generated function is_oneto_mask(::Val{mask}) where {mask}
    return is_oneto_mask(mask)
end



Base.@propagate_inbounds indices(arr) = indices(IndexStyle(arr), arr)
Base.@propagate_inbounds indices(::IndexLinear, arr) = LinearIndices(arr)
Base.@propagate_inbounds indices(::IndexCartesian, arr) = CartesianIndices(arr)

Base.@propagate_inbounds swizzleindex(dst, arr) = swizzleindex(IndexStyle(dst), dst, arr)

Base.@propagate_inbounds function swizzleindex(::IndexLinear, dst, arr)
    if is_nil_mask(Val(mask(arr)))
        return ConstantIndices(1, indices(arr.arg))
    elseif is_oneto_mask(Val(mask(arr)))
        return LinearIndices(dst)
    else
        return SwizzledIndices(arr)
    end
end

Base.@propagate_inbounds function swizzleindex(::IndexCartesian, dst, arr)
    if is_nil_mask(Val(mask(arr)))
        i = CartesianIndex(ntuple(n->1, Val(ndims(dst))))
        return ConstantIndices(i, indices(arr.arg))
    elseif is_oneto_mask(Val(mask(arr)))
        return CartesianIndices(dst)
    else
        return SwizzledIndices(arr)
    end
end

#FIXME This is a separate method for the scalar case so that swizzles can avoid
#recursion depth limiting.
Base.@propagate_inbounds function assign!(dst, index, src, drive::CartesianIndices{0})
    i = CartesianIndex()
    dst[index[i]] = src[i]
end

#FIXME This is a separate method for the scalar case so that swizzles can avoid
#recursion depth limiting.
Base.@propagate_inbounds function increment!(op::Op, dst, index, src, drive::CartesianIndices{0}) where {Op}
    i = CartesianIndex()
    i′ = index[i]
    dst[i′] = op(dst[i′], src[i])
end

Base.@propagate_inbounds function assign!(dst, index, src, drive)
    for i in drive
        dst[index[i]] = src[i]
    end
end

Base.@propagate_inbounds function increment!(op::Op, dst, index, src, drive) where {Op}
    for i in drive
        i′ = index[i]
        dst[i′] = op(dst[i′], src[i])
    end
end

@generated function assign!(dst, index, src, drive::CartesianIndices{N}) where {N}
    return quote
        Base.@_propagate_inbounds_meta
        @nloops $N i n -> drive.indices[n] begin
            i = CartesianIndex(@ntuple $N i)
            dst[index[i]] = src[i]
        end
    end
end

@generated function increment!(op::Op, dst, index, src, drive::CartesianIndices{N}) where {Op, N}
    return quote
        Base.@_propagate_inbounds_meta
        @nloops $N i n -> drive.indices[n] begin
            i = CartesianIndex(@ntuple $N i)
            i′ = index[i]
            dst[i′] = op(dst[i′], src[i])
        end
    end
end



struct SwizzledIndices{T, N, mask, Inds <: CartesianIndices{N}} <: AbstractArray{T, N}
    inds::Inds
    function SwizzledIndices{T, N, mask, Inds}(inds::Inds) where {T, N, mask, Inds}
        @assert T <: CartesianIndex{length(mask)}
        @assert max(0, mask...) <= ndims(inds)
        #TODO assert mask is unique
        return new{T, N, mask, Inds}(inds)
    end
end

Base.@propagate_inbounds SwizzledIndices(arr::SwizzledArray) = SwizzledIndices(Val(mask(arr)), CartesianIndices(arr.arg))
Base.@propagate_inbounds SwizzledIndices(mask, inds) = SwizzledIndices(mask, CartesianIndices(inds))
Base.@propagate_inbounds SwizzledIndices(mask, inds::CartesianIndices) = SwizzledIndices(Val(mask), inds)
Base.@propagate_inbounds function SwizzledIndices(::Val{mask}, inds::CartesianIndices) where {mask}
    return SwizzledIndices{CartesianIndex{length(mask)}, ndims(inds), mask, typeof(inds)}(inds)
end

@inline Base.size(arr::SwizzledIndices) = size(arr.inds)

@inline Base.axes(arr::SwizzledIndices) = axes(arr.inds)

@inline mask(arr::SwizzledIndices{<:Any, <:Any, _mask}) where {_mask} = _mask
@inline mask(::Type{<:SwizzledIndices{<:Any, <:Any, _mask}}) where {_mask} = _mask

Base.@propagate_inbounds function Base.getindex(arr::SwizzledIndices{T, N}, i::Vararg{Any, N})::T where {T, N}
    return CartesianIndex(masktuple(d->1, d->i[d], Val(mask(arr))))
end

struct ConstantIndices{T, N, i, Inds <: AbstractArray{<:Any, N}} <: AbstractArray{T, N}
    inds::Inds
    @inline function ConstantIndices{T, N, i, Inds}(inds::Inds) where {T, N, i, Inds}
        @assert i isa T
        return new{T, N, i, Inds}(inds)
    end
end

Base.@propagate_inbounds ConstantIndices(i, inds) = ConstantIndices(Val(i), inds)
Base.@propagate_inbounds function ConstantIndices(::Val{i}, inds) where {i}
    return ConstantIndices{typeof(i), ndims(inds), i, typeof(inds)}(inds)
end

@inline Base.size(arr::ConstantIndices) = size(arr.inds)
@inline Base.axes(arr::ConstantIndices) = axes(arr.inds)
@inline Base.IndexStyle(arr::ConstantIndices) = IndexStyle(arr.inds)
Base.@propagate_inbounds (Base.getindex(arr::ConstantIndices{T, N, i}, ::Vararg{Any, N})::T) where {T, N, i} = i
Base.@propagate_inbounds (Base.getindex(arr::ConstantIndices{T, 1, i}, ::Integer)::T) where {T, i} = i
Base.@propagate_inbounds (Base.getindex(arr::ConstantIndices{T, <:Any, i}, ::Integer)::T) where {T, i} = i

#function Base.Broadcast.preprocess(dest, arr::SwizzledArray{T, N, Op, mask, Arg}) where {T, N, Arg, Op, mask}
#    arg = preprocess(dest, arr.arg)
#    SwizzledArray{T, N, Op, mask, typeof(arg)}(arr.op, arg)
#end

"""
    `childstyle(::Type{<:AbstractArray}, ::BroadcastStyle)`

Broadcast styles are used to determine behavior of objects under broadcasting.
To customize the broadcasting behavior of a wrapper array, one can first declare
how the broadcast style should behave under broadcasting after the wrapper array
is applied by overriding the `childstyle` method.
"""
@inline childstyle(Arr::Type{<:AbstractArray}, ::BroadcastStyle) = BroadcastStyle(Arr)

@inline childstyle(Arr::Type{<:SwizzledArray}, ::DefaultArrayStyle) = DefaultArrayStyle{ndims(Arr)}()
@inline childstyle(Arr::Type{<:SwizzledArray}, ::BroadcastStyle) = DefaultArrayStyle{ndims(Arr)}()
@inline childstyle(::Type{<:SwizzledArray}, ::ArrayConflict) = ArrayConflict()
@inline childstyle(Arr::Type{<:SwizzledArray}, ::Style{Tuple}) = mask(Arr) == (1,) ? Style{Tuple}() : DefaultArrayStyle{ndims(Arr)}()

@inline function Broadcast.BroadcastStyle(Arr::Type{<:SwizzledArray})
    childstyle(Arr, BroadcastStyle(parent(Arr)))
end



@inline function Swizzles.ExtrudedArrays.keeps(arr::SwizzledArray)
    arg_keeps = keeps(arr.arg)
    arr_keeps = masktuple(d->Extrude(), d->arg_keeps[d], Val(mask(arr)))
    init_keeps = keeps(arr.init)
    return combinetuple(|, arr_keeps, init_keeps)
end

#=
function Swizzles.ExtrudedArrays.inferkeeps(Arr::Type{<:SwizzledArray})
    arg_keeps = inferkeeps(parent(Arr))
    masktuple(d->Extrude(), d->arg_keeps[d], Val(mask(Arr)))
end
=#

function Swizzles.ExtrudedArrays.lift_keeps(arr::SwizzledArray)
    return adopt(lift_keeps(parent(arr)), arr)
end

function Swizzles.ValArrays.lift_vals(arr::SwizzledArray)
    return adopt(lift_vals(parent(arr)), arr)
end

function Swizzles.NamedArrays.lift_names(arr::SwizzledArray, stuff)
    return adopt(lift_names(parent(arr), stuff), arr)
end
