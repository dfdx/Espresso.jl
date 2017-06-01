
let
    ex = :(y[i] = foo(x[j]))
    @test apply_guards(ex, [:(i == j)]) == :(y[i] = foo(x[i]))
end
