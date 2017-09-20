
struct BufCodeGen
    buf_var_name::Symbol
end


buffer_expr(var, buffer_var, sz_ex) =
    :($var = @get_or_create $buffer_var $(Expr(:quote, var)) $sz_ex)


function generate_code(codegen::BufCodeGen, g::EinGraph)
    g = eliminate_common(g)
    ex = to_buffered(g)
    buffer_var = codegen.buf_var_name
    init_exs = [buffer_expr(var, buffer_var, sz_ex) for (var, sz_ex) in g.ctx[:buff_exprs]
                if haskey(g, var) && getcategory(g[var]) != :input]
    res = Expr(:block, init_exs..., ex.args...)
    return res
end
