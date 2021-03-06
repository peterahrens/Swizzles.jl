module ShallowArrays

using Swizzles.WrapperArrays

using Base.Broadcast: BroadcastStyle
using Base: dataids, unaliascopy, unalias

export ShallowArray

"""
    ShallowArray

A convenience type for constructing simple wrapper arrays that behave almost
exactly like their parent. Provides default implementations of `AbstractArray`
methods. Subtypes of `ShallowArray` must define [`parent`](@ref) and
[`adopt`](@ref)

See also: [`parent`](@ref), [`adopt`](@ref)
"""
abstract type ShallowArray{T, N, Arg} <: AbstractArray{T, N} end

Base.parent(arr::ShallowArray) = throw(MethodError(parent, (arr)))
iswrapper(arr::ShallowArray) = true

IndexStyle(arr::ShallowArray) = IndexStyle(parent(arr))

Base.dataids(arr::ShallowArray) = dataids(parent(arr))
Base.unaliascopy(arr::A) where {A <:ShallowArray} = adopt(arr, unaliascopy(parent(arr)))::A
Base.unalias(dest, arr::A) where {A <:ShallowArray} = adopt(arr, unalias(dest, parent(arr)))::A

Base.eltype(::Type{<:ShallowArray{T}}) where {T} = T
Base.eltype(::ShallowArray{T}) where {T} = T

Base.ndims(::Type{<:ShallowArray{<:Any, N}}) where {N} = N
Base.ndims(::ShallowArray{<:Any, N}) where {N} = N

Base.size(arr::ShallowArray{<:Any, <:Any, <:AbstractArray}) = size(parent(arr))

Base.axes(arr::ShallowArray{<:Any, <:Any, <:AbstractArray}) = axes(parent(arr))

Base.@propagate_inbounds Base.getindex(arr::ShallowArray, inds...) = getindex(parent(arr), inds...)

Base.@propagate_inbounds Base.setindex!(arr::ShallowArray, val, inds...) = setindex!(parent(arr), val, inds...)

Base.eachindex(arr::ShallowArray) = eachindex(parent(arr))

@inline WrapperArrays.childstyle(::Type{<:ShallowArray}, S::BroadcastStyle) = S

@inline function Broadcast.BroadcastStyle(Arr::Type{<:ShallowArray{<:Any, <:Any, Arg}}) where {Arg}
    childstyle(Arr, BroadcastStyle(Arg))
end

function Base.show(io::IO, arr::ShallowArray{T, N, Arg}) where {T, N, Arg}
    print(io, typeof(arr))
    print(io, '(', parent(arr), ')')
    nothing
end

end
