
let
    ex = quote
        X = U * V .+ 2
        Y = U .+ 1
        Z = exp.(X .* Y)
    end
    inputs = [:U => rand(2,2), :V => rand(2,2)]
    bex = blassify(ex; inputs...)
    @test bex.args[1].args[1] == :A_mul_B!
    @test bex.args[end].head == :.=
end
