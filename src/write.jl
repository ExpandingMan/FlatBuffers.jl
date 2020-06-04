

function write!(io::IO, v::AbstractVector{<:BitsType})
    write(io, Int32(length(v))) + sum(x -> write(io, x), v)
end
function write!(io::IO, v::AbstractVector{<:AbstractString})
    write(io, Int32(ncodeunits(v))) + sum(x -> write(io, x), codeunits(v)) + write(io, 0x00)
end

# write single struct
write!(::StructType, io::IO, v) = write(n -> write!(io, getfield(v, n)), v)

function write!(io::IO, vt::VTable)
    write(io, nbytes(vt)) + write(io, vt.table_nbytes) + sum(x -> write(io, Int16(x)), vt)
end


function write!(::TableType, io::IO, t)

end
