
ex = :(z = x1*x2 + sin(x1))
@test (rdiff(ex, x1=1, x2=1) == Dict(:x1 => :(cos(x1) + x2), :x2 => :x1))
    
logistic(x) = 1 / (1 + exp(-x))
dlogistic(x) = logistic(x) * (1 - logistic(x))
dlogistic_expr = rdiff(logistic, [Float64])[:x]
x = 5
@test isapprox(eval(dlogistic_expr), dlogistic(x))

rdiff(:(x + logistic(x)), x=1) # at least check that no expression is thrown
           
function multi(x)
    y = 2x
    z = y^2
    return z
end

dexpr3 = rdiff(multi, [Float64])[:x]
x = 5
@test eval(dexpr3) == 8x
