
let
    nd = ExNode{:call}(:z, :(x + y))
    
    @test variable(nd) == :z
    @test varname(nd) == :z
    @test varidxs(nd) == []
    @test expr(nd) == :(x + y)
    @test value(nd) == nothing

    variable!(nd, :(z[i]))
    @test variable(nd) == :(z[i])
    @test varname(nd) == :z
    @test varidxs(nd) == [:i]

    expr!(nd, :(x[i] + y[i]))
    @test expr(nd) == :(x[i] + y[i])

    value!(nd, [1, 2, 3.])
    @test value(nd) == [1, 2, 3.]
end


let
    nd = ExNode{:call}(:z, :(x + y))
    @test to_expr(nd) == :(z = x + y)
end


let
    nd = ExNode{:call}(:(z[i]), :(x[i] + y[i]))
    @test to_expr(nd) == :(z[i] = x[i] + y[i])
end


let
    @test dependencies(ExNode{:constant}(:z, 42)) == []
    
    @test dependencies(ExNode{:input}(:z, 42)) == []

    @test dependencies(ExNode{:(=)}(:z, :x)) == [:x]
    @test dependencies(ExNode{:(=)}(:(z[i]), :(x[i]))) == [:x]
    
    @test dependencies(ExNode{:call}(:z, :(x + y))) == [:x, :y]
    @test dependencies(ExNode{:call}(:(z[i]), :(x[i] + y[i]))) == [:x, :y]

    @test dependencies(ExNode{:bcast}(:z, :(f.(x)))) == [:x]    
end


let
    nd = ExNode{:bcast}(:z, :(f.(x)))
    @test isindexed(nd) == false
    
    nd = ExNode{:bcast}(:z, :(f.(x[i])))
    @test isindexed(nd) == true
end
