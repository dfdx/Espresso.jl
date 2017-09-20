
struct EinCodeGen
end


function generate_code(::EinCodeGen, g::ExGraph)
    return to_einstein(g)
end

function generate_code(::EinCodeGen, g::EinGraph)
    return to_expr(g)
end
