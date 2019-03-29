module EachindexArrays

using Swizzles
using Swizzles.ShallowArrays
using Swizzles.ArrayifiedArrays
using Swizzles.WrapperArrays

using Base.Cartesian

using Swizzles: assign!, increment!

export EachindexArray, CartesianTiledIndices, Tile

struct EachindexArray{T, N, Arg, Indices} <: ShallowArray{T, N, Arg}
    arg::Arg
    indices::Indices
end

@inline EachindexArray(arg::AbstractArray, indices) = EachindexArray{eltype(arg), ndims(arg), typeof(arg), typeof(indices)}(arg, indices)

@inline Base.parent(arr::EachindexArray) = arr.arg
@inline WrapperArrays.iswrapper(arr::EachindexArray) = true
@inline WrapperArrays.adopt(arg, arr::EachindexArray) = EachindexArray(arg, arr.indices)

@inline function Base.eachindex(arr::EachindexArray)
    return arr.indices
end

@inline function Base.eachindex(arr::EachindexArray, args::AbstractArray...)
    return arr.indices
end

struct CartesianTiledIndices{N, Indices <: CartesianIndices{N}, tile_size} <: ShallowArray{CartesianIndex{N}, N, Indices}
    indices::Indices
    function CartesianTiledIndices{N, Indices, tile_size}(indices) where {N, Indices, tile_size}
        @assert tile_size isa Tuple{Vararg{Int, N}}
        return new{N, Indices, tile_size}(indices)
    end
end

@inline Base.parent(arr::CartesianTiledIndices) = arr.indices
@inline WrapperArrays.iswrapper(arr::CartesianTiledIndices) = true

@inline CartesianTiledIndices(indices::CartesianIndices, tile_size) = CartesianTiledIndices(indices, Val(tile_size))
@inline function CartesianTiledIndices(indices::CartesianIndices{N}, ::Val{tile_size}) where {N, tile_size}
    return CartesianTiledIndices{N, typeof(indices), tile_size}(indices)
end



@generated function Swizzles.assign!(dst, index, src, drive::CartesianTiledIndices{N, Indices, tile_size}) where {N, Indices, tile_size}
    function loop(axes, n)
        i_n = Symbol(:i, '_', n)
        j_n = Symbol(:j, '_', n)
        ii_n = Symbol(:ii, '_', n)
        II_n = Symbol(:II, '_', n)
        if n == 0
            return quote
                assign!(dst, index, src, CartesianIndices(($(axes...),)))
            end
        else
            return quote
                $i_n = 0
                for $ii_n = 1:$II_n
                    $j_n = $i_n + $(tile_size[n])
                    $(loop((:(drive.indices.indices[$n][($i_n + 1):$j_n]), axes...), n - 1))
                    $i_n = $j_n
                end
                $(loop((:(drive.indices.indices[$n][($i_n + 1):end]), axes...), n - 1))
            end
        end
    end
    return quote
        Base.@_propagate_inbounds_meta
        drive_size = size(drive.indices)
        @nexprs $N n -> II_n = fld(drive_size[n],tile_size[n])
        $(loop((), N))
    end
end

@generated function Swizzles.increment!(op::Op, dst, index, src, drive::CartesianTiledIndices{N, Indices, tile_size}) where {Op, N, Indices, tile_size}
    function loop(axes, n)
        i_n = Symbol(:i, '_', n)
        j_n = Symbol(:j, '_', n)
        ii_n = Symbol(:ii, '_', n)
        II_n = Symbol(:II, '_', n)
        if n == 0
            return quote
                increment!(op, dst, index, src, CartesianIndices(($(axes...),)))
            end
        else
            return quote
                $i_n = 0
                for $ii_n = 1:$II_n
                    $j_n = $i_n + $(tile_size[n])
                    $(loop((:(@inbounds drive.indices.indices[$n][($i_n + 1):$j_n]), axes...), n - 1))
                    $i_n = $j_n
                end
                $(loop((:(@inbounds drive.indices.indices[$n][($i_n + 1):end]), axes...), n - 1))
            end
        end
    end
    return quote
        Base.@_propagate_inbounds_meta
        drive_size = size(drive.indices)
        @nexprs $N n -> II_n = fld(drive_size[n],tile_size[n])
        $(loop((), N))
    end
end

struct Tile{_tile_size} <: Swizzles.Intercept end

@inline Tile(_tile_size...) = Tile{_tile_size}()

@inline function parse_tile_size(arr, _tile_size::Tuple{Vararg{Int}})
    return ntuple(n -> n <= length(_tile_size) ? _tile_size[n] : 1, ndims(arr))
end
@inline (ctr::Tile)(arg) = ctr(arrayify(arg))
@inline function(ctr::Tile{_tile_size})(arg::Arg) where {_tile_size, Arg <: AbstractArray}
    if @generated
        tile_size = parse_tile_size(arg, _tile_size)
        return :(return EachindexArray(arg, CartesianTiledIndices(CartesianIndices(arg), $tile_size)))
    else
        tile_size = parse_tile_size(arg, _tile_size)
        return EachindexArray(arg, CartesianTiledIndices(CartesianIndices(arg), tile_size))
    end
end

end
