import type { MiddlewareHandler } from 'hono'

// 2 tokens per second , allowing 10 rapid clicks small bucket named micro bucket
const MICRO_CAPACITY = 10
const MICRO_REFILL_RATE = 2 

// Refils in a whole day will run overlapping to the small bucket this is a bigger bucket named macro bucket 
const MACRO_CAPACITY = 500
const MACRO_REFILL_RATE = 500 / 86400 

export const advancedRateLimitMiddleware = (redis: any): MiddlewareHandler => async (c, next) => {
  // 1. Resolve User Identity
  const supabaseUser = c.get('supabase')?.auth?.getUser()
  const identifier = supabaseUser?.data?.user?.id || c.req.header('CF-Connecting-IP') || 'anonymous'
  
  const key = `ratelimit:dual:${identifier}`
  const now = Date.now() / 1000 // epoch time in seconds

  // Fetch State from Redis
  const data = await redis.hgetall(key)
  
  let lastMicroTokens = MICRO_CAPACITY
  let lastMacroTokens = MACRO_CAPACITY
  let lastCheck = now

  if (data && data.last_check) {
    lastMicroTokens = parseFloat(data.micro_tokens) || MICRO_CAPACITY
    lastMacroTokens = parseFloat(data.macro_tokens) || MACRO_CAPACITY
    lastCheck = parseFloat(data.last_check)
  }

  const elapsed = now - lastCheck // Thiss calculates the Del T (Used for behavioural profiling)

  // Lazy Quantization for both buckets 
  const currentMicroTokens = Math.min(MICRO_CAPACITY, lastMicroTokens + (elapsed * MICRO_REFILL_RATE))
  const currentMacroTokens = Math.min(MACRO_CAPACITY, lastMacroTokens + (elapsed * MACRO_REFILL_RATE))
  // This above code helps us check how many tokens refilled sinnce user last interaction

  //  Rate Limit Evaluation which will be checking that atleast both buckets has one token left 
  if (currentMicroTokens >= 1 && currentMacroTokens >= 1) {
    
    // Request Allowed: Deduct 1 token from both buckets and save back to redis so they arre ready for the next requests
    await redis.hset(key, {
      micro_tokens: String(currentMicroTokens - 1),
      macro_tokens: String(currentMacroTokens - 1),
      last_check: String(now)
    })
    
    // Set expiry to 24 hours to clear old memory while tracking macro scraping
    await redis.expire(key, 86400) 
    
    return await next()

  } else {
    // Request Denied: Determine which bucket failed to calculate cooldown
    let retryAfter = 0
    let violationReason = ''
    
    if (currentMicroTokens < 1) {
       retryAfter = Math.ceil((1 - currentMicroTokens) / MICRO_REFILL_RATE)
       violationReason = 'Rate Limit Exceeded: Fast burst detected.'
    } else {
       retryAfter = Math.ceil((1 - currentMacroTokens) / MACRO_REFILL_RATE)
       violationReason = 'Rate Limit Exceeded: Daily API allowance drained (SUSPICIOUS OF SCRAPING).'
    }

    return c.json({ 
      error: violationReason, 
      retry_after_seconds: retryAfter 
    }, 429)
  }
}
