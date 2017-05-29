
# types.jl - common types and aliases used throught the code


# name of operation in a :call node - either symbol or Module.symbol
const OpName = Union{Symbol, Expr}


# Wrapper around Expr adding `ex.head` to type parameters thus adding convenient
# type dispatching
mutable struct ExH{H}
    head::Symbol
    args::Vector
end

Base.show(io::IO, ex::ExH) = print(io, "ExH{:$(ex.head)}($(Expr(ex)))")

Base.convert(::Type{ExH}, ex::Expr) = ExH{ex.head}(ex.head, ex.args)
ExH(ex::Expr) = ExH{ex.head}(ex.head, ex.args)
Expr(ex::ExH) = Expr(ex.head, ex.args...)
