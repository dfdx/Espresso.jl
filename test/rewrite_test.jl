

@testset "rewrite" begin
    
    phs = Set([:x])
    @test matchex(:(_x ^ 2), :(a ^ 2)) == Dict(:_x => :a)
    @test matchex(:(x ^ 2), :(a ^ 2), phs=phs) == Dict(:x => :a)
    @test matchex(:(x ^ 2), :(a ^ 2)) == nothing

    phs = Set([:x, :y])
    @test rewrite(:(a + 2b), :(_x + 2_y), :(_x * _y)) == :(a * b)
    @test rewrite(:(a + 2b), :(x + 2y), :(x * y); phs=phs) == :(a * b)

    set_default_placeholders(Set([:x, :y]))
    @test rewrite(:(a + 2b), :(x + 2y), :(x * y)) == :(a * b)
    set_default_placeholders(Set(Symbol[]))

    @test tryrewrite(:(a + 2b), :(x + 2y), :(x * y); phs=[:x, :y]) == :(a * b)
    @test tryrewrite(:(a + 2b), :(x + 3y), :(x * y); phs=[:x, :y]) == nothing

    @test without(:(x * (m == n)), :(_i == _j)) == :x

    @test subs(:(x^n); n=2) == :(x^2)
    @test subs(:(x^n), Dict(:n => 2)) == :(x^2)
    @test subs(:(_mod._op); _mod=:Main, _op=:inc) == :(Main.inc)

    phs = Set([:x, :I])
    @test matchex(:(x[I...]), :(A[i,j,k]); phs=phs) == Dict(:x => :A, :I => [:i, :j, :k])
    @test matchex(:(foo(_args...)), :(foo(x, y))) == Dict(:_args => [:x, :y])

    ex = :(foo(bar(foo(A))))
    rules = [:(foo(x)) => :(quux(x)),
             :(bar(x)) => :(baz(x))]
    @test rewrite_all(ex, rules; phs=[:x]) == :(quux(baz(quux(A))))

    ex = :(foo(bar(foo(A))))
    pat = :(foo(x))
    rpat = :(quux(x))
    @test rewrite_all(ex, pat, rpat; phs=[:x]) == :(quux(bar(quux(A))))

    @test matchingex(:(_x + _y), :(a + a))
    @test !matchingex(:(_x + _y), :(a + a); exact=true)


    ex = :(foo(a, b, c))
    pat = :(foo(xs...))
    rpat = :(bar(xs...))
    @test rewrite(ex, pat, rpat; phs=[:xs]) == :(bar(a, b, c))
end

    
