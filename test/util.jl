@testset "util" begin
    using Swizzles: masktuple, imasktuple
    Is = [(),
          (1,),
          (nil,),
          (1, 2,),
          (nil, 2,),
          (2, nil,),
          (1, 2, 4,),
          (1, 2, nil, 4,),
          (1, nil, 3,)]
    for I in Is
        @test length(masktuple(+, -, I)) == length(I)
        @test masktuple(+, -, I) isa Tuple{Vararg{Int}}
        for j in 1:length(I)
            if I[j] isa Nil
                @test(masktuple(+, -, I)[j] == j)
            else
               @test(masktuple(+, -, I)[j] == -I[j])
            end
        end
        @test imasktuple(+, -, I, max(0, I...)) isa Tuple{Vararg{Int}}
        @test length(imasktuple(+, -, I, 0)) == 0
        @test length(imasktuple(+, -, I, 1)) == 1
        @test length(imasktuple(+, -, I, 2)) == 2
        for j in 1:length(I)
            if !(I[j] isa Nil)
                @test(imasktuple(+, -, I, max(0, I...))[I[j]] == -j)
            end
        end
        for j in 1:max(0, I...)
            if !(j in I)
                @test(imasktuple(+, -, I, max(0, I...))[j] == j)
            end
        end
    end
end
