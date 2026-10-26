function tests = UIStateTest
%UISTATETEST Dashboard controls: START/PAUSE/RESUME/STOP/RESET, field regeneration,
%   presets, dropdowns, locking and tab navigation (wraps golden/testDashboardV2).
    tests = functiontests(localfunctions);
end

function setupOnce(tc)
    tc.TestData.p = testSetupPaths();
end

function testDashboardSuite(tc)
    p = tc.TestData.p;
    evalc('ok = testDashboardV2(p);');
    verifyTrue(tc, ok, 'testDashboardV2 reported a failure');
end

function testTabNavigation(tc)
    app = AgriculturalDroneDashboardV2('Visible', 'off', 'AutoPlay', false);
    cl = onCleanup(@() delete(app));
    titles = {app.ModeTabs.Children.Title};
    for want = {'MISSION', 'PIPELINE BUILDER', 'ADVANCED OPTIONS', 'COMPARATIVE ANALYSIS', 'EXPERIMENTS'}
        verifyTrue(tc, any(strcmp(titles, want{1})), ['missing tab ' want{1}]);
    end
    for i = 1:numel(app.ModeTabs.Children)
        app.ModeTabs.SelectedTab = app.ModeTabs.Children(i);
        drawnow;
    end
    app.ModeTabs.SelectedTab = app.ModeTabs.Children(1);
    app.generateField(); app.startMission(); app.tickOnce(30);
    verifyEqual(tc, app.mode, 'PLAYING');
end
