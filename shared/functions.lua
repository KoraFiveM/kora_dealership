DealershipOrders = {}

function DealershipOrders.unitCost(price)
    local multiplier = tonumber(Config.orderPriceMultiplier) or 1.0
    return math.max(1, math.floor((tonumber(price) or 1) * multiplier))
end
