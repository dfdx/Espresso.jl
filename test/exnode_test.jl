
@testset "exnode" begin
    
    @testset "basic ops" begin
        nd = ExNode{:call}(:z, :(x + y))
        
        @test getvar(nd) == :z
        @test varname(nd) == :z
        @test varidxs(nd) == []
        @test getexpr(nd) == :(x + y)
        @test getvalue(nd) == nothing

        setvar!(nd, :(z[i]))
        @test getvar(nd) == :(z[i])
        @test varname(nd) == :z
        @test varidxs(nd) == [:i]

        setexpr!(nd, :(x[i] + y[i]))
        @test getexpr(nd) == :(x[i] + y[i])

        setvalue!(nd, [1, 2, 3.])
        @test getvalue(nd) == [1, 2, 3.]
    end


    @testset "simple node" begin
        nd = ExNode{:call}(:z, :(x + y))
        @test to_expr(nd) == :(z = x + y)
    end


    @testset "indexed node" begin
        nd = ExNode{:call}(:(z[i]), :(x[i] + y[i]))
        @test to_expr(nd) == :(z[i] = x[i] + y[i])
    end


    @testset "dependencies" begin
        @test dependencies(ExNode{:constant}(:z, 42)) == []
        
        @test dependencies(ExNode{:input}(:z, 42)) == []

        @test dependencies(ExNode{:(=)}(:z, :x)) == [:x]
        @test dependencies(ExNode{:(=)}(:(z[i]), :(x[i]))) == [:x]
        
        @test dependencies(ExNode{:call}(:z, :(x + y))) == [:x, :y]
        @test dependencies(ExNode{:call}(:(z[i]), :(x[i] + y[i]))) == [:x, :y]

        @test dependencies(ExNode{:bcast}(:z, :(f.(x)))) == [:x]    
    end


    @testset "broadcasting" begin
        nd = ExNode{:bcast}(:z, :(f.(x)))
        @test isindexed(nd) == false
        
        nd = ExNode{:bcast}(:z, :(f.(x[i])))
        @test isindexed(nd) == true
    end
    
end
