import Foundation
import CryptoKit
import CommonCrypto

// MARK: - Mnemonic Service (BIP39)
class MnemonicService {
    
    // MARK: - Properties
    static let shared = MnemonicService()
    private let wordList: [String]
    
    // MARK: - Enums
    enum MnemonicStrength: Int {
        case words12 = 128  // 128 bits = 12 words
        case words15 = 160  // 160 bits = 15 words
        case words18 = 192  // 192 bits = 18 words
        case words21 = 224  // 224 bits = 21 words
        case words24 = 256  // 256 bits = 24 words
        
        var wordCount: Int {
            return (rawValue + rawValue / 32) / 11
        }
    }
    
    enum MnemonicError: LocalizedError {
        case invalidWordCount
        case invalidWord(String)
        case invalidChecksum
        case invalidEntropy
        
        var errorDescription: String? {
            switch self {
            case .invalidWordCount:
                return "Invalid word count. Must be 12, 15, 18, 21, or 24 words"
            case .invalidWord(let word):
                return "Invalid word: \(word)"
            case .invalidChecksum:
                return "Invalid mnemonic checksum"
            case .invalidEntropy:
                return "Invalid entropy data"
            }
        }
    }
    
    // MARK: - Initialization
    init() {
        // Load BIP39 English word list
        self.wordList = MnemonicService.loadWordList()
    }
    
    private static func loadWordList() -> [String] {
        // Load complete BIP39 English word list (2048 words)
        guard let url = Bundle.main.url(forResource: "english", withExtension: "txt", subdirectory: "Resources/BIP39"),
              let wordString = try? String(contentsOf: url) else {
            // Fallback to embedded list if file not found
            return loadEmbeddedWordList()
        }
        
        return wordString.components(separatedBy: .newlines).filter { !$0.isEmpty }
    }
    
    private static func loadEmbeddedWordList() -> [String] {
        // Load from embedded string as fallback
        let wordListString = completeBIP39EnglishWordList
        return wordListString.components(separatedBy: "\n").filter { !$0.isEmpty }
    }
    
    // MARK: - Mnemonic Generation
    func generateMnemonic(strength: MnemonicStrength = .words24) throws -> String {
        // Generate random entropy
        let entropyBytes = strength.rawValue / 8
        var entropy = Data(count: entropyBytes)
        let result = entropy.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, entropyBytes, bytes.baseAddress!)
        }
        
        guard result == errSecSuccess else {
            throw MnemonicError.invalidEntropy
        }
        
        return try mnemonicFromEntropy(entropy)
    }
    
    func mnemonicFromEntropy(_ entropy: Data) throws -> String {
        let entropyBits = entropy.count * 8
        
        // Validate entropy length
        guard [128, 160, 192, 224, 256].contains(entropyBits) else {
            throw MnemonicError.invalidEntropy
        }
        
        // Calculate checksum
        let checksumBits = entropyBits / 32
        let hash = SHA256.hash(data: entropy)
        let checksumByte = hash.first(where: { _ in true }) ?? 0
        let checksum = checksumByte >> (8 - checksumBits)
        
        // Combine entropy and checksum
        var combined = entropy
        combined.append(checksum)
        
        // Convert to binary string
        let binaryString = combined.map { byte in
            String(byte, radix: 2).padLeft(toLength: 8, withPad: "0")
        }.joined()
        
        // Split into 11-bit chunks and convert to words
        let totalBits = entropyBits + checksumBits
        var words: [String] = []
        
        for i in stride(from: 0, to: totalBits, by: 11) {
            let startIndex = binaryString.index(binaryString.startIndex, offsetBy: i)
            let endIndex = binaryString.index(startIndex, offsetBy: 11)
            let chunk = String(binaryString[startIndex..<endIndex])
            
            if let index = Int(chunk, radix: 2) {
                words.append(wordList[index])
            }
        }
        
        return words.joined(separator: " ")
    }
    
    // MARK: - Mnemonic Validation
    func validateMnemonic(_ mnemonic: String) throws -> Bool {
        let words = mnemonic.lowercased().split(separator: " ").map(String.init)
        
        // Check word count
        guard [12, 15, 18, 21, 24].contains(words.count) else {
            throw MnemonicError.invalidWordCount
        }
        
        // Check all words are in word list
        var indices: [Int] = []
        for word in words {
            guard let index = wordList.firstIndex(of: word) else {
                throw MnemonicError.invalidWord(word)
            }
            indices.append(index)
        }
        
        // Convert words back to binary
        let binaryString = indices.map { index in
            String(index, radix: 2).padLeft(toLength: 11, withPad: "0")
        }.joined()
        
        // Split entropy and checksum
        let totalBits = words.count * 11
        let checksumBits = totalBits / 33
        let entropyBits = totalBits - checksumBits
        
        let entropyBinary = String(binaryString.prefix(entropyBits))
        let checksumBinary = String(binaryString.suffix(checksumBits))
        
        // Convert entropy to data
        var entropyData = Data()
        for i in stride(from: 0, to: entropyBinary.count, by: 8) {
            let startIndex = entropyBinary.index(entropyBinary.startIndex, offsetBy: i)
            let endIndex = entropyBinary.index(startIndex, offsetBy: min(8, entropyBinary.count - i))
            let byte = String(entropyBinary[startIndex..<endIndex])
            if let value = UInt8(byte.padRight(toLength: 8, withPad: "0"), radix: 2) {
                entropyData.append(value)
            }
        }
        
        // Calculate expected checksum
        let hash = SHA256.hash(data: entropyData)
        let expectedChecksumByte = hash.first(where: { _ in true }) ?? 0
        let expectedChecksum = expectedChecksumByte >> (8 - checksumBits)
        let expectedChecksumBinary = String(expectedChecksum, radix: 2).padLeft(toLength: checksumBits, withPad: "0")
        
        // Verify checksum
        guard checksumBinary == expectedChecksumBinary else {
            throw MnemonicError.invalidChecksum
        }
        
        return true
    }
    
    // MARK: - Seed Generation (BIP39)
    func mnemonicToSeed(_ mnemonic: String, passphrase: String = "") -> Data {
        let salt = "mnemonic" + passphrase
        return pbkdf2(password: mnemonic, salt: salt, iterations: 2048, keyLength: 64)
    }
    
    // MARK: - HD Key Derivation (BIP32)
    func generateMasterKey(from seed: Data) -> HDKey {
        let hmac = HMAC<SHA512>.authenticationCode(for: seed, using: SymmetricKey(data: "Bitcoin seed".data(using: .utf8)!))
        let hmacData = Data(hmac)
        
        let privateKey = hmacData.prefix(32)
        let chainCode = hmacData.suffix(32)
        
        return HDKey(
            privateKey: privateKey,
            chainCode: chainCode,
            depth: 0,
            index: 0,
            parentFingerprint: Data(repeating: 0, count: 4)
        )
    }
    
    func deriveKey(from parent: HDKey, at index: UInt32, hardened: Bool = false) -> HDKey {
        let hardenedOffset: UInt32 = 0x80000000
        let actualIndex = hardened ? index + hardenedOffset : index
        
        var data = Data()
        
        if hardened {
            // Hardened derivation: use private key
            data.append(0x00)
            data.append(parent.privateKey)
        } else {
            // Non-hardened derivation: use public key
            let publicKey = BitcoinService.shared.derivePublicKey(from: parent.privateKey, compressed: true)
            data.append(publicKey)
        }
        
        // Append index as big-endian
        var indexBytes = actualIndex.bigEndian
        data.append(Data(bytes: &indexBytes, count: 4))
        
        // Calculate HMAC
        let hmac = HMAC<SHA512>.authenticationCode(for: data, using: SymmetricKey(data: parent.chainCode))
        let hmacData = Data(hmac)
        
        let childKey = hmacData.prefix(32)
        let childChainCode = hmacData.suffix(32)
        
        // Add parent key to child key (modulo secp256k1 order)
        let childPrivateKey = addPrivateKeys(parent.privateKey, childKey)
        
        // Calculate fingerprint
        let publicKey = BitcoinService.shared.derivePublicKey(from: parent.privateKey, compressed: true)
        let hash = ripemd160(sha256(publicKey))
        let fingerprint = hash.prefix(4)
        
        return HDKey(
            privateKey: childPrivateKey,
            chainCode: childChainCode,
            depth: parent.depth + 1,
            index: actualIndex,
            parentFingerprint: fingerprint
        )
    }
    
    // MARK: - BIP44/49/84 Path Derivation
    func deriveAddress(from seed: Data, path: String, network: BitcoinService.Network = .mainnet) -> (privateKey: Data, address: String) {
        let masterKey = generateMasterKey(from: seed)
        let derivedKey = derivePath(from: masterKey, path: path)
        
        let publicKey = BitcoinService.shared.derivePublicKey(from: derivedKey.privateKey, compressed: true)
        
        // Determine address type from path
        let addressType: BitcoinService.AddressType
        if path.contains("m/44'") {
            addressType = .p2pkh  // Legacy
        } else if path.contains("m/49'") {
            addressType = .p2sh   // Nested SegWit
        } else if path.contains("m/84'") {
            addressType = .p2wpkh // Native SegWit
        } else if path.contains("m/86'") {
            addressType = .p2tr   // Taproot
        } else {
            addressType = .p2wpkh // Default to Native SegWit
        }
        
        let address = BitcoinService(network: network).generateAddress(from: publicKey, type: addressType)
        
        return (derivedKey.privateKey, address)
    }
    
    private func derivePath(from masterKey: HDKey, path: String) -> HDKey {
        let components = path.split(separator: "/").dropFirst() // Remove "m"
        
        var currentKey = masterKey
        
        for component in components {
            let isHardened = component.hasSuffix("'")
            let index = UInt32(isHardened ? component.dropLast() : component) ?? 0
            currentKey = deriveKey(from: currentKey, at: index, hardened: isHardened)
        }
        
        return currentKey
    }
    
    // MARK: - Helper Functions
    private func pbkdf2(password: String, salt: String, iterations: Int, keyLength: Int) -> Data {
        let passwordData = password.data(using: .utf8)!
        let saltData = salt.data(using: .utf8)!
        
        var derivedKey = Data(repeating: 0, count: keyLength)
        
        let result = derivedKey.withUnsafeMutableBytes { derivedKeyBytes in
            saltData.withUnsafeBytes { saltBytes in
                passwordData.withUnsafeBytes { passwordBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress, passwordData.count,
                        saltBytes.baseAddress, saltData.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA512),
                        UInt32(iterations),
                        derivedKeyBytes.baseAddress, keyLength
                    )
                }
            }
        }
        
        return result == kCCSuccess ? derivedKey : Data()
    }
    
    private func sha256(_ data: Data) -> Data {
        return SHA256.hash(data: data).data
    }
    
    private func ripemd160(_ data: Data) -> Data { RIPEMD160.hash(data) }
    
    private func addPrivateKeys(_ key1: Data, _ key2: Data) -> Data {
        // Proper scalar addition modulo curve order using libsecp256k1
        return CryptoService.shared.tweakAddPrivateKey(key1, tweak: key2) ?? Data()
    }
}

// MARK: - HD Key Structure
struct HDKey {
    let privateKey: Data
    let chainCode: Data
    let depth: UInt8
    let index: UInt32
    let parentFingerprint: Data
    
    var extendedPrivateKey: String {
        var data = Data()
        
        // Version bytes (xprv for mainnet)
        let version: UInt32 = 0x0488ade4
        var versionBytes = version.bigEndian
        data.append(Data(bytes: &versionBytes, count: 4))
        
        // Depth
        data.append(depth)
        
        // Parent fingerprint
        data.append(parentFingerprint)
        
        // Child index
        var indexBytes = index.bigEndian
        data.append(Data(bytes: &indexBytes, count: 4))
        
        // Chain code
        data.append(chainCode)
        
        // Private key (with 0x00 prefix)
        data.append(0x00)
        data.append(privateKey)
        
        return Base58.encode(data)
    }
}

// MARK: - String Extensions
extension String {
    func padLeft(toLength: Int, withPad: String) -> String {
        let padding = String(repeating: withPad, count: max(0, toLength - count))
        return padding + self
    }
    
    func padRight(toLength: Int, withPad: String) -> String {
        let padding = String(repeating: withPad, count: max(0, toLength - count))
        return self + padding
    }
}

// MARK: - Complete BIP39 English Word List (2048 words)
// This is the complete list, loaded from file or embedded as fallback
private let completeBIP39EnglishWordList = """
abandon
ability
able
about
above
absent
absorb
abstract
absurd
abuse
access
accident
account
accuse
achieve
acid
acoustic
acquire
across
act
action
actor
actress
actual
adapt
add
addict
address
adjust
admit
adult
advance
advice
aerobic
affair
afford
afraid
again
age
agent
agree
ahead
aim
air
airport
aisle
alarm
album
alcohol
alert
alien
all
alley
allow
almost
alone
alpha
already
also
alter
always
amateur
amazing
among
amount
amused
analyst
anchor
ancient
anger
angle
angry
animal
ankle
announce
annual
another
answer
antenna
antique
anxiety
any
apart
apology
appear
apple
approve
april
arch
arctic
area
arena
argue
arm
armed
armor
army
around
arrange
arrest
arrive
arrow
art
artefact
artist
artwork
ask
aspect
assault
asset
assist
assume
asthma
athlete
atom
attack
attend
attitude
attract
auction
audit
august
aunt
author
auto
autumn
average
avocado
avoid
awake
aware
away
awesome
awful
awkward
axis
baby
bachelor
bacon
badge
bag
balance
balcony
ball
bamboo
banana
banner
bar
barely
bargain
barrel
base
basic
basket
battle
beach
bean
beauty
because
become
beef
before
begin
behave
behind
believe
below
belt
bench
benefit
best
betray
better
between
beyond
bicycle
bid
bike
bind
biology
bird
birth
bitter
black
blade
blame
blanket
blast
bleak
bless
blind
blood
blossom
blouse
blue
blur
blush
board
boat
body
boil
bomb
bone
bonus
book
boost
border
boring
borrow
boss
bottom
bounce
box
boy
bracket
brain
brand
brass
brave
bread
breeze
brick
bridge
brief
bright
bring
brisk
broccoli
broken
bronze
broom
brother
brown
brush
bubble
buddy
budget
buffalo
build
bulb
bulk
bullet
bundle
bunker
burden
burger
burst
bus
business
busy
butter
buyer
buzz
cabbage
cabin
cable
cactus
cage
cake
call
calm
camera
camp
can
canal
cancel
candy
cannon
canoe
canvas
canyon
capable
capital
captain
car
carbon
card
cargo
carpet
carry
cart
case
cash
casino
castle
casual
cat
catalog
catch
category
cattle
caught
cause
caution
cave
ceiling
celery
cement
census
century
cereal
certain
chair
chalk
champion
change
chaos
chapter
charge
chase
chat
cheap
check
cheese
chef
cherry
chest
chicken
chief
child
chimney
choice
choose
chronic
chuckle
chunk
churn
cigar
cinnamon
circle
citizen
city
civil
claim
clap
clarify
claw
clay
clean
clerk
clever
click
client
cliff
climb
clinic
clip
clock
clog
close
cloth
cloud
clown
club
clump
cluster
clutch
coach
coast
coconut
code
coffee
coil
coin
collect
color
column
combine
come
comfort
comic
common
company
concert
conduct
confirm
congress
connect
consider
control
convince
cook
cool
copper
copy
coral
core
corn
correct
cost
cotton
couch
country
couple
course
cousin
cover
coyote
crack
cradle
craft
cram
crane
crash
crater
crawl
crazy
cream
credit
creek
crew
cricket
crime
crisp
critic
crop
cross
crouch
crowd
crucial
cruel
cruise
crumble
crunch
crush
cry
crystal
cube
culture
cup
cupboard
curious
current
curtain
curve
cushion
custom
cute
cycle
dad
damage
damp
dance
danger
daring
dash
daughter
dawn
day
deal
debate
debris
decade
december
decide
decline
decorate
decrease
deer
defense
define
defy
degree
delay
deliver
demand
demise
denial
dentist
deny
depart
depend
deposit
depth
deputy
derive
describe
desert
design
desk
despair
destroy
detail
detect
develop
device
devote
diagram
dial
diamond
diary
dice
diesel
diet
differ
digital
dignity
dilemma
dinner
dinosaur
direct
dirt
disagree
discover
disease
dish
dismiss
disorder
display
distance
divert
divide
divorce
dizzy
doctor
document
dog
doll
dolphin
domain
donate
donkey
donor
door
dose
double
dove
draft
dragon
drama
drastic
draw
dream
dress
drift
drill
drink
drip
drive
drop
drown
drum
dry
duck
dumb
dune
during
dust
dutch
duty
dwarf
dynamic
eager
eagle
early
earn
earth
easily
east
easy
echo
ecology
economy
edge
edit
educate
effort
egg
eight
either
elbow
elder
electric
elegant
element
elephant
elevator
elite
else
embark
embody
embrace
emerge
emotion
employ
empower
empty
enable
enact
end
endless
endorse
enemy
energy
enforce
engage
engine
enhance
enjoy
enlist
enough
enrich
enroll
ensure
enter
entire
entry
envelope
episode
equal
equip
era
erase
erode
erosion
error
erupt
escape
essay
essence
estate
eternal
ethics
evidence
evil
evoke
evolve
exact
example
excess
exchange
excite
exclude
excuse
execute
exercise
exhaust
exhibit
exile
exist
exit
exotic
expand
expect
expire
explain
expose
express
extend
extra
eye
eyebrow
fabric
face
faculty
fade
faint
faith
fall
false
fame
family
famous
fan
fancy
fantasy
farm
fashion
fat
fatal
father
fatigue
fault
favorite
feature
february
federal
fee
feed
feel
female
fence
festival
fetch
fever
few
fiber
fiction
field
figure
file
film
filter
final
find
fine
finger
finish
fire
firm
first
fiscal
fish
fit
fitness
fix
flag
flame
flash
flat
flavor
flee
flight
flip
float
flock
floor
flower
fluid
flush
fly
foam
focus
fog
foil
fold
follow
food
foot
force
forest
forget
fork
fortune
forum
forward
fossil
foster
found
fox
fragile
frame
frequent
fresh
friend
fringe
frog
front
frost
frown
frozen
fruit
fuel
fun
funny
furnace
fury
future
gadget
gain
galaxy
gallery
game
gap
garage
garbage
garden
garlic
garment
gas
gasp
gate
gather
gauge
gaze
general
genius
genre
gentle
genuine
gesture
ghost
giant
gift
giggle
ginger
giraffe
girl
give
glad
glance
glare
glass
glide
glimpse
globe
gloom
glory
glove
glow
glue
goat
goddess
gold
good
goose
gorilla
gospel
gossip
govern
gown
grab
grace
grain
grant
grape
grass
gravity
great
green
grid
grief
grit
grocery
group
grow
grunt
guard
guess
guide
guilt
guitar
gun
gym
habit
hair
half
hammer
hamster
hand
happy
harbor
hard
harsh
harvest
hat
have
hawk
hazard
head
health
heart
heavy
hedgehog
height
hello
helmet
help
hen
hero
hidden
high
hill
hint
hip
hire
history
hobby
hockey
hold
hole
holiday
hollow
home
honey
hood
hope
horn
horror
horse
hospital
host
hotel
hour
hover
hub
huge
human
humble
humor
hundred
hungry
hunt
hurdle
hurry
hurt
husband
hybrid
ice
icon
idea
identify
idle
ignore
ill
illegal
illness
image
imitate
immense
immune
impact
impose
improve
impulse
inch
include
income
increase
index
indicate
indoor
industry
infant
inflict
inform
inhale
inherit
initial
inject
injury
inmate
inner
innocent
input
inquiry
insane
insect
inside
inspire
install
intact
interest
into
invest
invite
involve
iron
island
isolate
issue
item
ivory
jacket
jaguar
jar
jazz
jealous
jeans
jelly
jewel
job
join
joke
journey
joy
judge
juice
jump
jungle
junior
junk
just
kangaroo
keen
keep
ketchup
key
kick
kid
kidney
kind
kingdom
kiss
kit
kitchen
kite
kitten
kiwi
knee
knife
knock
know
lab
label
labor
ladder
lady
lake
lamp
language
laptop
large
later
latin
laugh
laundry
lava
law
lawn
lawsuit
layer
lazy
leader
leaf
learn
leave
lecture
left
leg
legal
legend
leisure
lemon
lend
length
lens
leopard
lesson
letter
level
liar
liberty
library
license
life
lift
light
like
limb
limit
link
lion
liquid
list
little
live
lizard
load
loan
lobster
local
lock
logic
lonely
long
loop
lottery
loud
lounge
love
loyal
lucky
luggage
lumber
lunar
lunch
luxury
lyrics
machine
mad
magic
magnet
maid
mail
main
major
make
mammal
man
manage
mandate
mango
mansion
manual
maple
marble
march
margin
marine
market
marriage
mask
mass
master
match
material
math
matrix
matter
maximum
maze
meadow
mean
measure
meat
mechanic
medal
media
melody
melt
member
memory
mention
menu
mercy
merge
merit
merry
mesh
message
metal
method
middle
midnight
milk
million
mimic
mind
minimum
minor
minute
miracle
mirror
misery
miss
mistake
mix
mixed
mixture
mobile
model
modify
mom
moment
monitor
monkey
monster
month
moon
moral
more
morning
mosquito
mother
motion
motor
mountain
mouse
move
movie
much
muffin
mule
multiply
muscle
museum
mushroom
music
must
mutual
myself
mystery
myth
naive
name
napkin
narrow
nasty
nation
nature
near
neck
need
negative
neglect
neither
nephew
nerve
nest
net
network
neutral
never
news
next
nice
night
noble
noise
nominee
noodle
normal
north
nose
notable
note
nothing
notice
novel
now
nuclear
number
nurse
nut
oak
obey
object
oblige
obscure
observe
obtain
obvious
occur
ocean
october
odor
off
offer
office
often
oil
okay
old
olive
olympic
omit
once
one
onion
online
only
open
opera
opinion
oppose
option
orange
orbit
orchard
order
ordinary
organ
orient
original
orphan
ostrich
other
outdoor
outer
output
outside
oval
oven
over
own
owner
oxygen
oyster
ozone
pact
paddle
page
pair
palace
palm
panda
panel
panic
panther
paper
parade
parent
park
parrot
party
pass
patch
path
patient
patrol
pattern
pause
pave
payment
peace
peanut
pear
peasant
pelican
pen
penalty
pencil
people
pepper
perfect
permit
person
pet
phone
photo
phrase
physical
piano
picnic
picture
piece
pig
pigeon
pill
pilot
pink
pioneer
pipe
pistol
pitch
pizza
place
planet
plastic
plate
play
please
pledge
pluck
plug
plunge
poem
poet
point
polar
pole
police
pond
pony
pool
popular
portion
position
possible
post
potato
pottery
poverty
powder
power
practice
praise
predict
prefer
prepare
present
pretty
prevent
price
pride
primary
print
priority
prison
private
prize
problem
process
produce
profit
program
project
promote
proof
property
prosper
protect
proud
provide
public
pudding
pull
pulp
pulse
pumpkin
punch
pupil
puppy
purchase
purity
purpose
purse
push
put
puzzle
pyramid
quality
quantum
quarter
question
quick
quit
quiz
quote
rabbit
raccoon
race
rack
radar
radio
rail
rain
raise
rally
ramp
ranch
random
range
rapid
rare
rate
rather
raven
raw
razor
ready
real
reason
rebel
rebuild
recall
receive
recipe
record
recycle
reduce
reflect
reform
refuse
region
regret
regular
reject
relax
release
relief
rely
remain
remember
remind
remove
render
renew
rent
reopen
repair
repeat
replace
report
require
rescue
resemble
resist
resource
response
result
retire
retreat
return
reunion
reveal
review
reward
rhythm
rib
ribbon
rice
rich
ride
ridge
rifle
right
rigid
ring
riot
ripple
risk
ritual
rival
river
road
roast
robot
robust
rocket
romance
roof
rookie
room
rose
rotate
rough
round
route
royal
rubber
rude
rug
rule
run
runway
rural
rush
sad
saddle
sadness
safe
sail
salad
salmon
salon
salt
salute
same
sample
sand
satisfy
satoshi
sauce
sausage
save
say
scale
scan
scare
scatter
scene
scheme
school
science
scissors
scorpion
scout
scrap
screen
script
scrub
sea
search
season
seat
second
secret
section
security
seed
seek
segment
select
sell
seminar
senior
sense
sentence
series
service
session
settle
setup
seven
shadow
shaft
shallow
share
shed
shell
sheriff
shield
shift
shine
ship
shiver
shock
shoe
shoot
shop
short
shoulder
shove
shrimp
shrug
shuffle
shy
sibling
sick
side
siege
sight
sign
silent
silk
silly
silver
similar
simple
since
sing
siren
sister
situate
six
size
skate
sketch
ski
skill
skin
skirt
skull
slab
slam
sleep
slender
slice
slide
slight
slim
slogan
slot
slow
slush
small
smart
smile
smoke
smooth
snack
snake
snap
sniff
snow
soap
soccer
social
sock
soda
soft
solar
soldier
solid
solution
solve
someone
song
soon
sorry
sort
soul
sound
soup
source
south
space
spare
spatial
spawn
speak
special
speed
spell
spend
sphere
spice
spider
spike
spin
spirit
split
spoil
sponsor
spoon
sport
spot
spray
spread
spring
spy
square
squeeze
squirrel
stable
stadium
staff
stage
stairs
stamp
stand
start
state
stay
steak
steel
stem
step
stereo
stick
still
sting
stock
stomach
stone
stool
story
stove
strategy
street
strike
strong
struggle
student
stuff
stumble
style
subject
submit
subway
success
such
sudden
suffer
sugar
suggest
suit
summer
sun
sunny
sunset
super
supply
supreme
sure
surface
surge
surprise
surround
survey
suspect
sustain
swallow
swamp
swap
swarm
swear
sweet
swift
swim
swing
switch
sword
symbol
symptom
syrup
system
table
tackle
tag
tail
talent
talk
tank
tape
target
task
taste
tattoo
taxi
teach
team
tell
ten
tenant
tennis
tent
term
test
text
thank
that
theme
then
theory
there
they
thing
this
thought
three
thrive
throw
thumb
thunder
ticket
tide
tiger
tilt
timber
time
tiny
tip
tired
tissue
title
toast
tobacco
today
toddler
toe
together
toilet
token
tomato
tomorrow
tone
tongue
tonight
tool
tooth
top
topic
topple
torch
tornado
tortoise
toss
total
tourist
toward
tower
town
toy
track
trade
traffic
tragic
train
transfer
trap
trash
travel
tray
treat
tree
trend
trial
tribe
trick
trigger
trim
trip
trophy
trouble
truck
true
truly
trumpet
trust
truth
try
tube
tuition
tumble
tuna
tunnel
turkey
turn
turtle
twelve
twenty
twice
twin
twist
two
type
typical
ugly
umbrella
unable
unaware
uncle
uncover
under
undo
unfair
unfold
unhappy
uniform
unique
unit
universe
unknown
unlock
until
unusual
unveil
update
upgrade
uphold
upon
upper
upset
urban
urge
usage
use
used
useful
useless
usual
utility
vacant
vacuum
vague
valid
valley
valve
van
vanish
vapor
various
vast
vault
vehicle
velvet
vendor
venture
venue
verb
verify
version
very
vessel
veteran
viable
vibrant
vicious
victory
video
view
village
vintage
violin
virtual
virus
visa
visit
visual
vital
vivid
vocal
voice
void
volcano
volume
vote
voyage
wage
wagon
wait
walk
wall
walnut
want
warfare
warm
warrior
wash
wasp
waste
water
wave
way
wealth
weapon
wear
weasel
weather
web
wedding
weekend
weird
welcome
west
wet
whale
what
wheat
wheel
when
where
whip
whisper
wide
width
wife
wild
will
win
window
wine
wing
wink
winner
winter
wire
wisdom
wise
wish
witness
wolf
woman
wonder
wood
wool
word
work
world
worry
worth
wrap
wreck
wrestle
wrist
write
wrong
yard
year
yellow
you
young
youth
zebra
zero
zone
zoo
"""
