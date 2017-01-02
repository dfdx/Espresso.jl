
# diff_rules.jl - differentiation rules for basic operations.


## basic rules

@diff_rule (-x::Number) 1 -1

# product

@diff_rule *(x::Number, y::Number) 1 y
@diff_rule *(x::Number, y::AbstractArray) 1 sum(y)
@diff_rule *(x::AbstractArray, y::Number) 1 y
@diff_rule *(x::AbstractArray, y::AbstractArray) 1 y'

@diff_rule *(x::Number, y::Number) 2 x
@diff_rule *(x::Number, y::AbstractArray) 2 x
@diff_rule *(x::AbstractArray, y::Number) 2 sum(x)
@diff_rule *(x::AbstractArray, y::AbstractArray) 2 x'

# elementwise product

@diff_rule .*(x::Number, y::Number) 1 y
@diff_rule .*(x::Number, y::AbstractArray) 1 sum(y)
@diff_rule .*(x::AbstractArray, y::Number) 1 y
@diff_rule .*(x::AbstractArray, y::AbstractArray) 1 y

@diff_rule .*(x::Number, y::Number) 2 x
@diff_rule .*(x::Number, y::AbstractArray) 2 x
@diff_rule .*(x::AbstractArray, y::Number) 2 sum(x)
@diff_rule .*(x::AbstractArray, y::AbstractArray) 2 x

# other arithmetic operations

@diff_rule (x::Number ^ n::Number) 1 (n * x.^(n-1))
@diff_rule (a::Number ^ x::Number) 2 (log(a) * a.^x)
@diff_rule (x::Number .^ n::Number) 1 (n * x.^(n-1))
@diff_rule (a::Number .^ x::Number) 2 (log(a) * a.^x)
# @diff_rule (x::Number ^ 2::Number) 1 (2x)

@diff_rule (x::Number / y::Number) 1 (x / y)
@diff_rule (x::AbstractArray / y::Number) 1 x ./ y
@diff_rule (n::Number / x::Real) 2 (-n * x .^ -2.0)
@diff_rule (x::AbstractArray / y::Real) 2 (sum(-x .* y) / (y * y))

@diff_rule (x::Any + y::Any) 1 1
@diff_rule (x::Any + y::Any) 2 1
@diff_rule (x::Any + y::Any + z::Any) 1 1
@diff_rule (x::Any + y::Any + z::Any) 2 1
@diff_rule (x::Any + y::Any + z::Any) 3 1
@diff_rule (w::Any + x::Any + y::Any + z::Any) 1 1
@diff_rule (w::Any + x::Any + y::Any + z::Any) 2 1
@diff_rule (w::Any + x::Any + y::Any + z::Any) 3 1
@diff_rule (w::Any + x::Any + y::Any + z::Any) 4 1

@diff_rule (x::Any .+ y::Any) 1 1
@diff_rule (x::Any .+ y::Any) 2 1

@diff_rule (x::Any - y::Any) 1 1
@diff_rule (x::Any - y::Any) 2 -1

@diff_rule (x::Any .- y::Any) 1 1
@diff_rule (x::Any .- y::Any) 2 -1

@diff_rule sum(x::Number) 1 1
@diff_rule sum(x::AbstractArray) 1 ones(size(x))

# dot product

@diff_rule dot(x::Number, y::Number) 1 y
@diff_rule dot(x::Number, y::Number) 2 x

@diff_rule vecdot(x::AbstractVector, y::AbstractVector) 1 y
@diff_rule vecdot(x::AbstractVector, y::AbstractVector) 2 x

@diff_rule dot(x::AbstractArray, y::AbstractArray) 1 y
@diff_rule dot(x::AbstractArray, y::AbstractArray) 2 x

# trigonomeric functions

@diff_rule sin(x::Number) 1 cos(x)
@diff_rule sin(x::AbstractArray) 1 cos(x)
@diff_rule cos(x::Number) 1 -sin(x)
@diff_rule cos(x::AbstractArray) 1 -sin(x)

@diff_rule tan(x::Number) 1 (1. + tan(x)  * tan(x))
@diff_rule tan(x::AbstractArray) 1 (1. + tan(x) .* tan(x))

@diff_rule sinh(x::Number) 1 cosh(x)
@diff_rule sinh(x::AbstractArray) 1 cosh(x)

@diff_rule cosh(x::Number) 1 sinh(x)
@diff_rule cosh(x::AbstractArray) 1 sinh(x)

@diff_rule tanh(x::Number) 1 (1. - tanh(x)  * tanh(x))
@diff_rule tanh(x::AbstractArray) 1 (1. - tanh(x) .* tanh(x))

@diff_rule asin(x::Number) 1 (1 / sqrt(1 - x*x))
@diff_rule asin(x::AbstractArray) 1 (1 ./ sqrt(1 - x.*x))

@diff_rule acos(x::Number) 1 (1  / sqrt(1 - x *x))
@diff_rule acos(x::AbstractArray) 1 (-1 ./ sqrt(1 - x.*x))

@diff_rule atan(x::Number) 1 (1  / (1 + x*x))
@diff_rule atan(x::AbstractArray) 1 (1 ./ (1 + x.*x))

# sqrt

@diff_rule sqrt(x::Number) 1 (0.5 * x^(-0.5))
@diff_rule sqrt(x::AbstractVector) 1 (0.5 .* x .^ (-0.5))

# exp, log

@diff_rule exp(x::Number) 1 exp(x)
@diff_rule exp(x::AbstractArray) 1 exp(x)

@diff_rule log(x::Number) 1 (1/x)

# abs

@diff_rule abs(x::Number) 1 (sign(x) * x)
@diff_rule abs(x::AbstractArray) 1 (sign(x) .* x)

# min, max

@diff_rule max(x::Number, y::Number) 1 (x > y)
@diff_rule max(x::Number, y::Number) 2 (y > x)

@diff_rule min(x::Number, y::Number) 1 (x < y)
@diff_rule min(x::Number, y::Number) 2 (y < x)

@diff_rule sign(x::Any) 1 0.

# transpose

@diff_rule transpose(x::Number) 1 1
@diff_rule transpose(x::AbstractArray) 1 transpose(ones(size(x)))

@diff_rule size(x::Any) 1 0.
@diff_rule size(x::Any, y::Any) 1 0.
@diff_rule size(x::Any, y::Any) 2 0.

# relu

@diff_rule relu(x::Number) 1 (x .> 0) # TODO: should reference concrete module?
# TODO: use qualified names when adding diff rules!
