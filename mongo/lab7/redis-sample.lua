-- Measure the actual cache payload and a daily ZSET in a disposable Redis instance.
local input = cjson.decode(ARGV[1])
local day = ARGV[2]
local page = input.publicPage
local cache = 'afisha:v1:page:' .. page._id
local rank = 'afisha:v1:rank:{' .. day .. '}:approved'
local stage = rank .. ':build'
local json = cjson.encode(page)
redis.call('SET', cache, json, 'EX', 300)
assert(cjson.decode(redis.call('GET',cache))._id == page._id)
redis.call('DEL',cache)
assert(not redis.call('GET',cache))
redis.call('SET',cache,json,'EX',300)
local now = tonumber(redis.call('TIME')[1])
local cutoff = (math.floor(now/86400)+8)*86400
local function publish(rows)
  redis.call('DEL',stage)
  for _, row in ipairs(rows) do
    redis.call('ZADD', stage, row.score, row._id)
  end
  if #rows == 0 then
    redis.call('DEL',rank)
  else
    redis.call('EXPIREAT',stage,cutoff)
    redis.call('RENAME',stage,rank)
  end
end
publish({{score=7,_id=page._id}})
publish({{score=2,_id=page._id}})
assert(tonumber(redis.call('ZSCORE',rank,page._id)) == 2)
publish({})
assert(redis.call('EXISTS',rank) == 0)
publish(input.ranking)
assert(redis.call('ZCARD',rank) == #input.ranking)
local top = redis.call('ZREVRANGE',rank,0,0,'WITHSCORES')
assert(tonumber(top[2]) == input.ranking[1].score)
local actualBytes = redis.call('MEMORY','USAGE',rank,'SAMPLES',0)
local rankTTL = redis.call('TTL',rank)
-- Size the forecast at exactly 1,000 members with the project's slug length.
local capacity = 'afisha:v1:rank:{2099-01-01}:approved'
for i=0,999 do redis.call('ZADD',capacity,(i%23)+1,string.format('s7-page-%04d',i)) end
local memberCount=redis.call('ZCARD',capacity)
local rankingBytes=redis.call('MEMORY','USAGE',capacity,'SAMPLES',0)
local cacheBytes=redis.call('MEMORY','USAGE',cache,'SAMPLES',0)
local activePages=2400
local liveRanks=8
local steady=activePages*cacheBytes+liveRanks*rankingBytes
local peak=steady+rankingBytes
assert(memberCount==1000 and cacheBytes>0 and rankTTL>0 and rankTTL<=8*86400)
local version=string.match(redis.call('INFO','server'),'redis_version:([%d%.]+)')
return cjson.encode({passed=true,cacheRefill=true,rankDecreaseAndEmpty=true,redisVersion=version,sourceDay=input.day,measurementDay=day,
  pageKey=cache,payloadBytes=string.len(json),pageBytes=cacheBytes,pageTTL=redis.call('TTL',cache),
  rankingMembers=#input.ranking,rankingBytes=actualBytes,rankingTTL=rankTTL,cutoff=cutoff,
  projectedMembers=memberCount,projectedRankingBytes=rankingBytes,activePageKeys=activePages,
  activeRankKeys=liveRanks,steadyBytes=steady,peakWithBuildBytes=peak,budgetWith30PercentBytes=math.ceil(peak*1.3)})
