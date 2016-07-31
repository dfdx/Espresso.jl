
@deriv_rule (x::Float64 ^ n::Int) 1 (n * x^(n-1))
@deriv_rule (a::Float64 ^ x::Int) 2 (log(a) * a^x)
@deriv_rule (x::Float64 + y::Float64) 1 x
@deriv_rule (x::Float64 + y::Float64) 2 y

@deriv_rule (x::Float64 = y::Float64) 1 1.
@deriv_rule (x::Int64 = y::Int64) 1 1.
