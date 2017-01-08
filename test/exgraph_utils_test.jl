
# propagate size
let
    inputs = [:W => rand(3,4),
              :T => rand(3,4,5)]
    
    ex = quote
        v[i,k] = T[i,j,k]
        y[i] = W[i,j]
        z = W[i,j]
    end
    g = ExGraph(ex; inputs...)

    propagate_size!(g)
    sizes = g.ctx[:sizes]
    
    @test sizes[:z] == :(())
    @test sizes[:y] == :(size(W,1))
    @test sizes[:v] == :(size(T,1,3))
end
