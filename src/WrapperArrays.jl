module WrapperArrays

import LinearAlgebra

export iswrapper, adopt, storage, childstyle

using Base.Broadcast: BroadcastStyle

#=
    This file defines
        1. What it means to be a "simple wrapper array". Any simple wrapper
        must define the `adopt` function, which describes how to construct
        analogous wrapper arrays with new parents, and specialize Base.parent.
        2. Corresponding methods for "simple wrapper arrays" in Base.
        3. A conveience type `ShallowArray` which defines several pass-through
        methods for easy construction of wrapper arrays.
    Ideally, numbers 1 and 2 should live in Adapt.jl, (note that `adapt` can be
    implemented with adopt).

    Wrappers need to define
        parent
        adopt
        iswrapper?
        dataids?
        unaliascopy?
        alias?

=#

"""
    adopt(child, arg)

Wrap `arg` in an analogous wrapper array to `child`. This function should
create an array with the same semantics as `child`. Generally, if `p` is
mostly the same array as `parent(x)`, it should hold that `adopt(x, p)` is
mostly the same array as `x`.

See also: [`parent`](@ref), [`iswrapper`](@ref)
"""
adopt(arr, arg) = throw(MethodError(adopt, (arr, arg)))

"""
    storage(arr)

Return the deepest ancestor of the array `arr`. If `arr` is a wrapper array,
returns `storage(parent(arr))`. Otherwise, returns `arr`.

See also: [`parent`](@ref), [`iswrapper`](@ref)
"""
function storage(f::F, arr) where {F}
    if iswrapper(arr)
        return parent(arr)
    else
        return arr
    end
end

"""
    iswrapper(arr)

A trait function which returns `true` if and only if `arr !== parent(arr)`. We
reccommend specializing this function with hard-coded implementations for custom
array types to improve type inference of wrapper array functions like
[`storage`](@ref).

See also: [`parent`](@ref)
"""
iswrapper(arr) = arr !== parent(arr)

#Base
iswrapper(::Array) = false

iswrapper(::LinearAlgebra.Transpose) = true
adopt(arr::LinearAlgebra.Transpose, arg::AbstractVecOrMat) = LinearAlgebra.transpose(arg)

iswrapper(::LinearAlgebra.Adjoint) = true
adopt(arr::LinearAlgebra.Adjoint, arg::AbstractVecOrMat) = LinearAlgebra.adjoint(arg)

iswrapper(::SubArray) = true
adopt(arr::SubArray, arg) = SubArray(arg, parentindices(arr))

iswrapper(::LinearAlgebra.LowerTriangular) = true
adopt(arr::LinearAlgebra.LowerTriangular, arg) = LinearAlgebra.LowerTriangular(arg)

iswrapper(::LinearAlgebra.UnitLowerTriangular) = true
adopt(arr::LinearAlgebra.UnitLowerTriangular, arg) = LinearAlgebra.UnitLowerTriangular(arg)

iswrapper(::LinearAlgebra.UpperTriangular) = true
adopt(arr::LinearAlgebra.UpperTriangular, arg) = LinearAlgebra.UpperTriangular(arg)

iswrapper(::LinearAlgebra.UnitUpperTriangular) = true
adopt(arr::LinearAlgebra.UnitUpperTriangular, arg) = LinearAlgebra.UnitUpperTriangular(arg)

iswrapper(::LinearAlgebra.Diagonal) = true
adopt(arr::LinearAlgebra.Diagonal, arg) = LinearAlgebra.Diagonal(arg)

iswrapper(::Base.ReshapedArray) = true
adopt(arr::Base.ReshapedArray, arg) = reshape(arg, arr.dims)

iswrapper(::PermutedDimsArray) = true
function adopt(arg::Arg, arr::PermutedDimsArray{<:Any,N,perm,iperm}) where {T,N,perm,iperm,Arg<:AbstractArray{T, N}}
    return PermutedDimsArray{T,N,perm,iperm,Arg}(arg)
end

"""
    `childstyle(::Type{<:AbstractArray}, ::BroadcastStyle)`

Broadcast styles are used to determine behavior of objects under broadcasting.
To customize the broadcasting behavior of a wrapper array, one can first declare
how the broadcast style should behave under broadcasting after the wrapper array
is applied by overriding the `childstyle` method.
"""
@inline childstyle(Arr::Type{<:AbstractArray}, ::BroadcastStyle) = BroadcastStyle(Arr)

end
