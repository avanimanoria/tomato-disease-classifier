function tests = ExistingSuitesTest
%EXISTINGSUITESTEST The earlier function-style suites stay green.
    tests = functiontests(localfunctions);
end

function setupOnce(tc)
    tc.TestData.p = testSetupPaths();
end

function testSuiteAdvancedRouting(tc), run1(tc, 'testAdvancedRouting'); end
function testSuiteAdvancedPhysics(tc), run1(tc, 'testAdvancedPhysics'); end
function testSuiteResearchExtensions(tc), run1(tc, 'testResearchExtensions'); end

function run1(tc, fn)
    p = tc.TestData.p; %#ok<NASGU>
    txt = evalc(['ok = ' fn '(p);']);
    verifyTrue(tc, ok, [fn ' reported a failure:' newline strjoin(regexp(txt, '[^\n]*FAIL[^\n]*', 'match'), newline)]);
end
