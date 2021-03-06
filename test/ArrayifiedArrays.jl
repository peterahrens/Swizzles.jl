using Swizzles.ArrayifiedArrays

foo(x) = x

@testset "ArrayifiedArrays" begin
    for arg in ((1, 2, 3.0), (1, 2, 3), (), [1, 2, 3.0], [1, 2, 3], [], [1 2; 3 4], transpose([1, 2]))
        @test foo.(ArrayifiedArray(arg)) == foo.(arg)
    end
    @test ArrayifiedArray([1 2; 3 4])[3] == 2
    @test arrayify(Delay().(1 .+ 1))[] == 2
end
