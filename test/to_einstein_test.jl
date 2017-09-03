
let
    ex = :(y = W * x + b)
    iex = to_einstein(ex; W=rand(2,3), x=rand(3), b=rand(2))
    
    @test length(iex.args) == 3

    # a stupid way to check that at least index of the first element is  correct
    @test iex.args[2].args[1].args[2:end] == [:i]
end


let
    ex = quote
        y = sum(x, 1)
        z = sum(y)
    end
    x = rand(3, 4)
    inputs = [:x => x]
    iex = to_einstein(ex; inputs...)
    @test iex.args[3] == :(y[i, j] = sum_1(x[:, j]))
end


let
    ex = quote
        y = mean(x, 2)
        z = sum(y)
    end
    x = rand(3, 4)
    inputs = [:x => x]
    iex = to_einstein(ex; inputs...)
    @test iex.args[3] == :(y[i, j] = sum_2(x[i, :]) / length(x[::]))
end
