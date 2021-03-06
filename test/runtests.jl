using Swizzles
using Test

@testset "Swizzles" begin
    include("Swizzles.jl")
    include("ShallowArrays.jl")
    include("EachindexArrays.jl")
    include("ExtrudedArrays.jl")
    include("ValArrays.jl")
    include("NamedArrays.jl")
    include("Virtuals.jl")
    include("ArrayifiedArrays.jl")
    include("StylishArrays.jl")
    include("PermutedArrays.jl")
    include("util.jl")
end
