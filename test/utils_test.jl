
@testset "utils" begin

    ex1 = :(foo(x, y=1, z=2))
    ex2 = :(foo(x; y=1, z=2))
    args, kw_args = parse_call_args(ex1)
    @test args == [:x]
    @test kw_args == Dict(:y => 1, :z => 2)

    @test without_keywords(ex1) == :(foo(x))
    @test without_keywords(ex2) == :(foo(x))
    @test with_keywords(:(foo(x)), Dict(:y => 1, :z => 2)) == ex2
    
    @test parse_call_expr(ex1) == (:foo, [:x], Dict(:y => 1, :z => 2))
    @test parse_call_expr(ex2) == (:foo, [:x], Dict(:y => 1, :z => 2))
end
