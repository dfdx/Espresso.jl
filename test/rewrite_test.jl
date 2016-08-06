
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
