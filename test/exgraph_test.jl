
let
    g = ExGraph()
    g = ExGraph(ctx=[:foo => 42], x=1)
    @test g.ctx[:foo] == 42
    @test value(g[1]) == 1    
end

let
    g = ExGraph(:(z = (x + y)^2); x=1, y=1)
    @test length(g.tape) == 5     # check that collapse_assignment!() removed extra var
    @test varname(g[5]) == :z
    @test evaluate!(g) == 4

    g = ExGraph(:(z = (x .+ y).^2); x=ones(3), y=ones(3))
    @test evaluate!(g) == [4.0, 4.0, 4.0]

    g = EinGraph(:(z = (x[i] .+ y[i]) * I[i]); x=ones(3), y=ones(3))
    @test length(g.tape) == 4     # check that collapse_assignment!() removed extra var
    @test varname(g[4]) == :z
    @test evaluate!(g) == 6.0
end


let
    # test parse!()
    ex = quote
        M[i,j] = exp.(u[i] .* v[j])
        x[i] = M[i,j]
        y[i] = 2 * x[i]
        z = y[i] * I[i]
    end
    g = EinGraph(ex; u=rand(3), v=rand(3))
    @test category(g[1]) == :input
    @test category(g[3]) == :call
    @test category(g[4]) == :bcast
    @test category(g[5]) == :(=)
    @test category(g[6]) == :constant

    # test node access methods
    @test g[4] == g[:M] && g[:M] == g["M"]

    # test variable index inference
    @test varidxs(g[3]) == [:i,:j]

    ex = :(M = u'v)
    g = ExGraph(ex; u=rand(3), v=rand(3))
    @test category(g[3]) == :call
    @test expr(g[3]) == :(transpose(u))
end
