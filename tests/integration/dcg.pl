% Definite Clause Grammar tests

% Simple terminal matching
det --> [the].
noun --> [cat].
noun --> [dog].
verb --> [sleeps].
verb --> [eats].

% Phrase rules
noun_phrase --> det, noun.
verb_phrase --> verb.
sentence --> noun_phrase, verb_phrase.

% EXPECT: true
?- phrase(det, [the]).

% EXPECT: true
?- phrase(noun, [cat]).

% EXPECT: false
?- phrase(noun, [the]).

% EXPECT: true
?- phrase(noun_phrase, [the, cat]).

% EXPECT: true
?- phrase(sentence, [the, dog, sleeps]).

% EXPECT: false
?- phrase(sentence, [cat, the, sleeps]).

% With variables
% EXPECT: X = [the]
?- phrase(det, X).

% phrase/3 with remainder
% EXPECT: true
?- phrase(det, [the, cat], [cat]).

% EXPECT: true
?- phrase(noun_phrase, [the, cat, sleeps], [sleeps]).

% Agreement (parametric DCG)
s(N) --> np(N), vp(N).
np(sg) --> [the], [cat].
np(pl) --> [the], [cats].
vp(sg) --> [sleeps].
vp(pl) --> [sleep].

% EXPECT: X = sg
?- phrase(s(X), [the, cat, sleeps]).

% EXPECT: X = pl
?- phrase(s(X), [the, cats, sleep]).

% EXPECT: false
?- phrase(s(_), [the, cat, sleep]).
