
let
    ex = :(y[i] = foo(x[j]))
    @test Espresso.apply_guards(ex, [:(i == j)]) == :(y[i] = foo(x[i]))
end
