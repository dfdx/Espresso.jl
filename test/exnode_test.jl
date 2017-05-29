
let
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
