
typealias Symbolic Union{Expr, Symbol, GlobalRef}
typealias Numeric Union{Number, Array}

# name of operation in a :call node - either symbol or module + symbol
typealias OpName AbstractString

@runonce type ExH{H}
    head::Symbol
    args::Vector
    typ::Any
end

to_exh(ex::Expr) = ExH{ex.head}(ex.head, ex.args, ex.typ)
to_expr(exh::ExH) = Expr(exh.head, exh.args..., exh.typ)
