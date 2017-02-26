
# types.jl - common types and aliases used throught the code

const Symbolic = Union{Expr, Symbol}
const Numeric = Union{Number, Array}

# name of operation in a :call node - either symbol or Module.symbol
const OpName = Union{Symbol, Expr}

const ExIndex = Union{Symbol, Int}

# Wrapper around Expr adding `ex.head` to type parameters thus adding convenient
# type dispatching
@runonce type ExH{H}
    head::Symbol
    args::Vector
end

to_exh(ex::Expr) = ExH{ex.head}(ex.head, ex.args)
to_expr(exh::ExH) = Expr(exh.head, exh.args...)

Base.convert(::Type{ExH}, ex::Expr) = ExH{ex.head}(ex.head, ex.args)
ExH(ex::Expr) = ExH{ex.head}(ex.head, ex.args)

@runonce type ExCall{Op}
    head::Symbol
    args::Vector
end

to_excall(ex::Expr) = ExCall{ex.args[1]}(ex.head, ex.args)
to_expr(exc::ExCall) = Expr(exc.head, exc.args...)


function exprlike(x)
    flds = Set(fieldnames(x))
    return in(:head, flds) && in(:args, flds)
end

