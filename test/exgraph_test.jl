
let
    g = ExGraph()
    g = ExGraph(ctx=[:foo => 42], x=1)
    @test g.ctx[:foo] == 42
    @test getvalue(g[1]) == 1    
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
    @test getcategory(g[1]) == :input
    @test getcategory(g[3]) == :call
    @test getcategory(g[4]) == :bcast
    @test getcategory(g[5]) == :(=)
    @test getcategory(g[6]) == :constant

    # test node access methods
    @test g[4] == g[:M] && g[:M] == g["M"]

    # test variable index inference
    @test varidxs(g[3]) == [:i,:j]

    ex = :(M = u'v)
    g = ExGraph(ex; u=rand(3), v=rand(3))
    @test getcategory(g[3]) == :call
    @test getexpr(g[3]) == :(transpose(u))
end


let
    g = ExGraph(:(x = u + v; z = 2x))
    nd = ExNode{:call}(:y, :(x - 1))
    insert!(g, 2, nd)
    @test varname(g[2]) == :y

    nds = ExGraph(:(t1 = u + x; t2 = u - x)).tape
    insert!(g, 3, nds)
    @test varname(g[3]) == :t1
    @test varname(g[4]) == :t2

    delete!(g, 3)
    @test length(g) == 5
    delete!(g, :t2)
    @test length(g) == 4
    
end
