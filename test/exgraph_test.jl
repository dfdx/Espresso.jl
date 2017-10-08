
@testset "exgraph" begin
    let
        g = ExGraph()
        g = ExGraph(ctx=[:foo => 42], x=1)
        @test g.ctx[:foo] == 42
        @test getvalue(g[1]) == 1    
    end

    let
        g = ExGraph(:(z = (x + y)^2); x=1, y=1)
        @test length(g.tape) == 5     # check that fuse_assigned() removed extra var
        @test varname(g[5]) == :z
        @test evaluate!(g) == 4

        g = ExGraph(:(z = (x .+ y).^2); x=ones(3), y=ones(3))
        @test evaluate!(g) == [4.0, 4.0, 4.0]

        # deprecated
        # g = EinGraph(:(z = x[i] .+ y[i]); x=ones(3), y=ones(3))
        # @test length(g.tape) == 3     # check that fuse_assigned() removed extra var
        # @test varname(g[3]) == :z
        # @test evaluate!(g) == 6.0
    end


    let
        # deprecated
        # # test parse!()
        # ex = quote
        #     M[i,j] = exp.(u[i] .* v[j])
        #     x[i] = M[i,j]
        #     y[i] = 2 * x[i]
        #     z = y[i]
        # end
        # g = EinGraph(ex; u=rand(3), v=rand(3))
        # @test getcategory(g[1]) == :input
        # @test getcategory(g[3]) == :call
        # @test getcategory(g[4]) == :bcast    
        # @test getcategory(g[6]) == :call

        # # test node access methods
        # @test g[end] == g[:z] && g[:z] == g["z"]

        # # test variable index inference
        # @test varidxs(g[3]) == [:i,:j]

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

        nds = ExGraph(:(t1 = u + x; t2 = t1 - x)).tape
        insert!(g, 3, nds)
        @test varname(g[3]) == :t1
        @test varname(g[4]) == :t2

        delete!(g, 3)
        @test length(g) == 5
        delete!(g, :t2)
        @test length(g) == 4
        
    end


    let
        # test graph with :opaque nodes
        g = ExGraph(:(y = 2x); x=rand(2))
        push!(g, ExNode{:opaque}(:z, :(x .* 3y)))    
        rep_g = reparse(g)
        @test getvar(g[3]) == getvar(rep_g[3])
        @test evaluate!(g) == evaluate!(rep_g)

        rw_nd = rewrite(g[3], :(Z = X * Y), :(Z = X .* Y'); phs=[:X, :Y, :Z])
        @test getcategory(rw_nd) == :opaque
        @test getvalue(rw_nd) == nothing        # value should be cleared
    end
end
