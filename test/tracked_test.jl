@testset "tracked" begin

    ex = quote
        x2 = W * x .+ b
        x3 = exp.(x2)
        x4 = reshape(x3, 15)
        y = sum(x4)
    end


    inputs = [:W => rand(3,4); :x => rand(4,5); :b => rand(3)]
    g1 = ExGraph(ex; inputs...)
    g2 = ExGraph(ex; ctx=Dict(:method => :track), inputs...)

    @test evaluate!(g1) == evaluate!(g2)
end
