
let
    ex = :(y = W * x + b)
    iex = to_einstein(ex; W=rand(2,3), x=rand(3), b=rand(2))
    
    @test length(iex.args) == 3

    # a stupid way to check that at least index of the first element is  correct
    @test iex.args[2].args[1].args[2:end] == [:i]
end
