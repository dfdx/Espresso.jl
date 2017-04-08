
let
    @test split_indexed(:x)  == (:x, [])
    @test split_indexed(:(x[i,j])) == (:x, [:i,:j])
end


let
    @test get_vars(:(z = x + y)) == [:z, :x, :y]
    @test get_vars(:(z = x[i] + y)) == [:z, :(x[i]), :y]
    @test get_vars(:(z = x + (f(y)))) == [:z, :x]
    @test get_vars(:(z = x + (f(y))); rec=true) == [:z, :x, :y]
    @test get_vars(:(z = x + (f.(y))); rec=true) == [:z, :x, :y]
    @test get_vars(:(z = x + (f(y[i]))); rec=true) == [:z, :x, :(y[i])]
end


let
    ex = :(z = x[i] + y[i])
    @test get_var_names(ex) == [:z, :x, :y]
    @test get_indices(ex) == [[], [:i], [:i]]

    ex = :(z = x[i] + f(y[i]))
    @test get_var_names(ex) == [:z, :x]
    @test get_var_names(ex; rec=true) == [:z, :x, :y]

    @test get_indices(ex) == [[], [:i]]
    @test get_indices(ex; rec=true) == [[], [:i], [:i]]
end
