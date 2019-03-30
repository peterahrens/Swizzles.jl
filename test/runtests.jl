using Swizzles
using Test

@testset "Swizzles" begin
    include("Swizzles.jl")
    include("ShallowArrays.jl")
    include("EachindexArrays.jl")
    include("ExtrudedArrays.jl")
    include("ValArrays.jl")
    include("NamedArrays.jl")
    include("ArrayifiedArrays.jl")
    include("GeneratedArrays.jl")
    include("util.jl")
end
