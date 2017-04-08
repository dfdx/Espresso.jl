
let
    ex = quote
        M[i,j] = exp.(u[i] .* v[j])
        x[i] = M[i,j]
        y[i] = 2 * x[i]
        z = y[i] * I[i]
    end
    g = ExGraph(ex; u=rand(3), v=rand(3))
    propagate_size!(g)

    sizes = g.ctx[:sizes]
    @test sizes[:M] == :((size(u), size(v)))
    @test sizes[:x] == :((size(u)))
    @test sizes[:z] == :(())
end
