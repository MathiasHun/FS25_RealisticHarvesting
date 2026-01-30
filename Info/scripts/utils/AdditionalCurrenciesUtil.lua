--
-- AdditionalCurrenciesUtil
--
-- @author Rockstar
-- @date 30/11/2024
--


AdditionalCurrenciesUtil = {}

function AdditionalCurrenciesUtil.prependedFunction(oldTarget, oldFunc, newTarget, newFunc)
	local superFunc = oldTarget[oldFunc]

	oldTarget[oldFunc] = function(...)
		newTarget[newFunc](newTarget, ...)
		superFunc(...)
	end
end

function AdditionalCurrenciesUtil.appendedFunction(oldTarget, oldFunc, newTarget, newFunc)
	local superFunc = oldTarget[oldFunc]

	oldTarget[oldFunc] = function(...)
		superFunc(...)
		newTarget[newFunc](newTarget, ...)
	end
end

function AdditionalCurrenciesUtil.overwrittenFunction(oldTarget, oldFunc, newTarget, newFunc, isStatic)
	local superFunc = oldTarget[oldFunc]

	if isStatic then
		oldTarget[oldFunc] = function(...)
			return newTarget[newFunc](newTarget, superFunc, ...)
		end
	else
		oldTarget[oldFunc] = function(self, ...)
			return newTarget[newFunc](newTarget, self, superFunc, ...)
		end
	end
end

function AdditionalCurrenciesUtil.makeCallback(target, func)
	return function(...)
		return func(target, ...)
	end
end