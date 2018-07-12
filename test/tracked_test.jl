import Espresso: value


struct Point
    a
    b
end

@testset "tracked data" begin
    n = 1.0
    a = rand(5)
    s = Point(1.0, 2.0)

    g = ExGraph()
    tn = tracked(g, :x, n)
    ta = tracked(g, :y, a)
    ts = tracked(g, :z, s)

    @test value(tn) == n
    @test value(ta) == a
    @test value(ts).a == s.a && value(ts).b == s.b

    @test istracked(tn)
    @test istracked(ta)
    @test istracked(ts)
end


@testset "tracking" begin
    ex = quote
        x2 = W * x .+ b
        x3 = exp.(x2)
        x4 = reshape(x3, 15)
        y = sum(x4)
    end
    inputs = [:W => rand(3,4); :x => rand(4,5); :b => rand(3)]
    g1 = ExGraph(ex; inputs...)
    g2 = ExGraph(ex; ctx=Dict(:method => :track), inputs...)
    @test evaluate!(g1) == evaluate!(g2)
end


sum_mean_with_dims(x) = sum(mean(x; dims=2); dims=1)

@testset "tracked_exgraph" begin
    g = tracked_exgraph(sum_mean_with_dims, rand(3, 4))
    @test matchingex(:(mean(_; dims=2)), getexpr_kw(g[2]))
    @test matchingex(:(sum(_; dims=1)), getexpr_kw(g[3]))
end


@testset "tracked struct" begin
    p = Point(1.0, 2.0)
    ex = :(z = p.a + p.b)
    g = ExGraph()
    eval_tracked!(g, ex, :p => p)

    @test g[1] isa ExNode{:field}
    @test g[2] isa ExNode{:field}
    @test g[3] isa ExNode{:call}

    # nested structs
    p = Point(Point(1.0, 1.0), Point(2.0, 2.0))
    ex = :(z = p.b.b - p.a.a)
    g = ExGraph()
    eval_tracked!(g, ex, :p => p)

    @test g[1] isa ExNode{:field}
    @test g[2] isa ExNode{:field}
    @test g[3] isa ExNode{:field}
    @test g[4] isa ExNode{:field}
    @test g[5] isa ExNode{:call}
end
