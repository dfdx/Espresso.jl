
phs = Set([:x])
@test get(matchex(:(_x ^ 2), :(a ^ 2))) == Dict(:_x => :a)
@test get(matchex(:(x ^ 2), :(a ^ 2), phs=phs)) == Dict(:x => :a)
@test isnull(matchex(:(x ^ 2), :(a ^ 2)))

phs = Set([:x, :y])
@test rewrite(:(a + 2b), :(_x + 2_y), :(_x * _y)) == :(a * b)
@test rewrite(:(a + 2b), :(x + 2y), :(x * y); phs=phs) == :(a * b)

set_default_placeholders(Set([:x, :y]))
@test rewrite(:(a + 2b), :(x + 2y), :(x * y)) == :(a * b)
set_default_placeholders(Set(Symbol[]))

@test get(tryrewrite(:(a + 2b), :(x + 2y), :(x * y); phs=[:x, :y])) == :(a * b)
@test isnull(tryrewrite(:(a + 2b), :(x + 3y), :(x * y); phs=[:x, :y]))

@test without(:(x * (m == n)), :(_i == _j)) == :x

@test subs(:(x^n); n=2) == :(x^2)
@test subs(:(x^n), Dict(:n => 2)) == :(x^2)
@test subs(:(_mod._op); _mod=:Main, _op=:inc) == :(Main.inc)

phs = Set([:x, :I])
@test get(matchex(:(x[I...]), :(A[i,j,k]); phs=phs)) == Dict(:x => :A, :I => [:i, :j, :k])
@test get(matchex(:(foo(_args...)), :(foo(x, y)))) == Dict(:_args => [:x, :y])
