@testset "Powers" begin
    using Swizzles.Powers
    a = sqrt(prevfloat(typemax(Float64)))
    x = power(a, 2)
    @test root(x) ≈ a
    @test root(x + x + x + x) ≈ 2 * a
    @test root(power(0, 2) + x) ≈ a
    @test root(x + power(0, 2)) ≈ a
    @test root(power(0, 2) + power(0, 2)) ≈ 0
    y = power(Inf, 2)
    z = power(-Inf, 2)
    @test root(y) == Inf
    @test root(y + z) == Inf

end
