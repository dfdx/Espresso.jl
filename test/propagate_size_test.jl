
let
    ex = quote
        M[i,j] = exp.(u[i] .* v[j])
        x[i] = M[i,j]
        y[i] = 2 * x[i]
        z = y[i]
    end
    g = EinGraph(ex; u=rand(3), v=rand(3))
    propagate_size!(g)

    sizes = g.ctx[:sizes]    
    @test sizes[:x] == :(size(u))
    @test sizes[:z] == :(())
end



let
    inputs = [:W => rand(3,4),
              :T => rand(3,4,5)]
    
    ex = quote
        v[i,k] = T[i,j,k]
        y[i] = W[i,j]
        z = W[i,j]
    end
    g = EinGraph(ex; inputs...)
    propagate_size!(g)
    
    sizes = g.ctx[:sizes]    
    @test sizes[:z] == :(())
   
end
