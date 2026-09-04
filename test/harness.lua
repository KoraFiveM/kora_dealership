local H = { total = 0, failed = 0 }

function H.equal(actual, expected, message)
    H.total = H.total + 1
    if actual ~= expected then
        H.failed = H.failed + 1
        print(('  [FAIL] %s (expected %s, got %s)'):format(message, tostring(expected), tostring(actual)))
    else
        print(('  [PASS] %s'):format(message))
    end
end

function H.ok(value, message) H.equal(value == true, true, message) end

function H.finish()
    print(('qbdealership: %d passed, %d failed'):format(H.total - H.failed, H.failed))
    if H.failed > 0 then os.exit(1) end
end

return H
