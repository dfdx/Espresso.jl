
typealias Symbolic Union{Expr, Symbol}
typealias Numeric Union{Number, Array}

@runonce type ExH{H}
    head::Symbol
    args::Vector
    typ::Any
end

to_exh(ex::Expr) = ExH{ex.head}(ex.head, ex.args, ex.typ)
to_expr(exh::ExH) = Expr(exh.head, exh.args..., exh.typ)
