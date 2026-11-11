DealershipOrders = {}

function DealershipOrders.unitCost(price)
    local multiplier = tonumber(Config.orderPriceMultiplier) or 1.0
    return math.max(1, math.floor((tonumber(price) or 1) * multiplier))
end

-- The price range a seller may adjust a vehicle's listed price into, as a percentage
-- of that price in either direction (clamped to 1 and to Config.maxPrice). Shared by
-- the client (to size the price slider) and the server (to re-validate what came back).
function DealershipOrders.priceBounds(basePrice, maxOverridePercent)
    local price = tonumber(basePrice) or 0
    local pct = math.max(0, tonumber(maxOverridePercent) or 0)
    local delta = price * (pct / 100)

    local minPrice = math.max(1, math.floor(price - delta))
    local maxPrice = math.min(tonumber(Config.maxPrice) or math.huge, math.ceil(price + delta))
    if maxPrice < minPrice then maxPrice = minPrice end

    return minPrice, maxPrice
end
