


Base.@propagate_inbounds function parentindex(arr::SubArray, i...)
    return Base.reindex(Base.parentindices(arr), i)
end

Base.@propagate_inbounds function parentindex(arr::SwizzledArray, i::Integer)
    return parentindex(arr, CartesianIndices(arr)[i])
end

Base.@propagate_inbounds function parentindex(arr::SwizzledArray, i::CartesianIndex)
    return parentindex(arr, Tuple(i)...)
end

Base.@propagate_inbounds function parentindex(arr::SwizzledArray{<:Any, 1}, i::Integer)
    return invoke(parentindex, Tuple{typeof(arr), Any}, arr, i)
end

Base.@propagate_inbounds function parentindex(arr::SwizzledArray{<:Any, N}, i::Vararg{Any, N}) where {N}
    arg_axes = axes(arr.arg)
    imasktuple(d->Base.Slice(arg_axes[d]), d->i[d], Val(mask(arr)), Val(ndims(arr.arg)))
end


"""
   parentindex(arr, i...)

   For all wrapper arrays arr such that `arr` involves an index remapping,
   return the indices into `parent(arr)` which affect the indices `i` of `arr`.

   See also: [`swizzle`](@ref).
"""
parentindex

Base.@propagate_inbounds function childindex(arr::SwizzledArray{<:Any, N}, i::Integer) where {N}
    if is_nil_mask(Val(mask(arr)))
        return (1,)
    elseif is_oneto_mask(Val(mask(arr)))
        return (i,)
    else
        return childindex(arr, CartesianIndices(arr.arg)[i])
    end
end

Base.@propagate_inbounds function childindex(arr::SwizzledArray{<:Any, N}, i::CartesianIndex) where {N}
    if is_nil_mask(Val(mask(arr)))
        return (CartesianIndex(ntuple(n->1, length(mask(arr)))),)
    elseif is_oneto_mask(Val(mask(arr)))
        return (i,)
    else
        return childindex(arr, Tuple(i)...)
    end
end

Base.@propagate_inbounds function childindex(arr::SwizzledArray{<:Any, N, <:Any, <:Any, <:AbstractArray, <:AbstractArray{<:Any, M}}, i::Vararg{Integer, M}) where {N, M}
    if is_nil_mask(Val(mask(arr)))
        return ntuple(n->1, length(mask(arr)))
    elseif is_oneto_mask(Val(mask(arr)))
        return i
    else
        masktuple(d->1, d->i[d], Val(mask(arr)))
    end
end

"""
   childindex(arr, i...)

   For all wrapper arrays arr such that `arr` involves an index remapping,
   return the indices into `arr` which affect the indices `i` of `parent(arr)`.

   See also: [`swizzle`](@ref).
"""
childindex

#=
@inline function remask(inds, inds′, mask)
    _remask(map(Base.index_dimsum, inds), map(Base.index_dimsum, inds′), Val(mask))
end
@generated function _remask(inds, inds′, ::Val{mask}) where {mask}
    return quote
        Base.@_inline_meta
        $(__remask(map(i -> !(i <: Tuple{}), Tuple(inds.parameters)),
                   map(i -> !(i <: Tuple{}), Tuple(inds′.parameters)), mask))
    end
end
function __remask(inds, inds′, mask)
    if first(inds)
        if first(mask) === nil
            return (nil, __remask(Base.tail(inds), inds′, Base.tail(mask))...)
        else
            return (count(inds′[1:first(mask)]), __remask(Base.tail(inds), inds′, Base.tail(mask))...)
        end
    else
        return __remask(Base.tail(inds), inds′, Base.tail(mask))
    end
end
__remask(::Tuple{}, inds′, ::Tuple{}) = ()
=#
