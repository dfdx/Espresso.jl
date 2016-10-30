
ex = :(z = x1*x2 + sin(x1))
@test (rdiff(ex, inputs=Dict(:x1=>1, :x2=>1)) ==
       Dict(:x1 => :(cos(x1) + x2), :x2 => :x1))
    
logistic(x) = 1 / (1 + exp(-x))
dlogistic(x) = logistic(x) * (1 - logistic(x))
dlogistic_expr = rdiff(logistic; inputs=Dict(:x=>1))[:x]
x = 5
@test isapprox(eval(dlogistic_expr), dlogistic(x))

@test (rdiff(:(x + logistic(x)), inputs=Dict(:x=>1)) ==
       Dict(:x => :(1.0 + exp(-x) * (1 + exp(-x)) ^ -2)))
           

function multi(x)
    y = 2x
    z = y^2
    return z
end

@test rdiff(multi, inputs=Dict(:x=>1)) == Dict(:x => :(8x))
