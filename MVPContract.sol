pragma solidity ^0.4.23;

library StringUtils {
    function uint2str(uint i) internal pure returns (string) {
        if (i == 0) return "0";
        uint j = i;
        uint len;
        while (j != 0){
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint k = len - 1;
        while (i != 0){
            bstr[k--] = byte(48 + i % 10);
            i /= 10;
        }
        return string(bstr);
    }

    function strConcat(string _a, string _b, string _c) internal pure returns (string) {
        bytes memory _ba = bytes(_a);
        bytes memory _bb = bytes(_b);
        bytes memory _bc = bytes(_c);
        string memory abc;
        uint k = 0;
        uint i;
        bytes memory babc;
        if (_ba.length==0)
        {
            abc = new string(_bc.length);
            babc = bytes(abc);
        }
        else
        {
            abc = new string(_ba.length + _bb.length+ _bc.length);
            babc = bytes(abc);
            for (i = 0; i < _ba.length; i++) babc[k++] = _ba[i];
            for (i = 0; i < _bb.length; i++) babc[k++] = _bb[i];
        }
        for (i = 0; i < _bc.length; i++) babc[k++] = _bc[i];
        return string(babc);
    }
}

contract Owned {
    address public owner;
    address private candidate;

    event OwnerChanged(address indexed previousOwner, address indexed newOwner);

    function Owned()  {
        owner = msg.sender;
    }
    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }
    function changeOwner(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Invalid address");
        candidate = newOwner;
    }
    function confirmOrnerChanging() public {
        require(candidate == msg.sender, "Only owner candidate can confirm owner changing");
        emit OwnerChanged(owner, candidate);
        owner = candidate;
    }
}

contract TestOperations is Owned {

    uint public minFee = 1 finney;

    struct Test {
        uint startTime;
        uint finishTime;
        address owner;
        string scenario;
        uint reward;         // reward for one tester;
        address[] testers;
        TestStatus status;
        bool isRewardPaid;
    }

    enum  TestStatus {
        NONE,                                           //0 - test not created
        WAITING,                                        //1 - waiting for testers
        READY,                                          //2 - test ready to run
        RUNNING,                                        //3 - test running
        FINISHED                                       //4 - test finished
    }
    enum  TesterState {
        NONE,                                           //0 - tester not attached to test
        ATTACHED,                                       //1 - tester attached to test
        READY,                                          //2 - tester ready to run test
        FINISHED                                        //3 - tester finished test
    }

    struct TestResult {
        string row;
    }

    Test[] internal _tests;
    mapping(uint => mapping(address => TesterState)) internal _testerStates; // testId => testerAdress => TesterState
    mapping(uint => string[]) internal _testsResults; // testId => TestResult

    function createOrder(uint _startTime, address[] _testers, string _scenario) payable public  {
        require(msg.value >= minFee, "Customer is greedy");
        require(_testers.length > 0, "Too few testers");
        require(_testers.length < 10, "Too many testers");
        require(_startTime > now + 5 * 60, "It is impossible to create test in the past");

        Test memory _test;
        _test.startTime = _startTime;
        _test.owner = msg.sender;
        _test.scenario = _scenario;
        _test.testers = _testers;
        _test.reward = msg.value / _testers.length;   //reward for one tester
        _test.isRewardPaid = false;
        _test.status = TestStatus.WAITING;

        uint256 newTestId = _tests.push(_test) - 1;

        for(uint i = 0; i < _testers.length; i++) {
            _testerStates[newTestId][_testers[i]] = TesterState.ATTACHED;
        }

        emit TestCreated(newTestId, _tests[newTestId].reward);
    }

    function payReward(uint testId) testExist(testId)
    testAtStatus(testId, TestStatus.FINISHED) internal {
        require(!_tests[testId].isRewardPaid, "Reward already paid");

        _tests[testId].isRewardPaid = true;
        for(uint i = 0; i < _tests[testId].testers.length; i++) {
            _tests[testId].testers[i].transfer( _tests[testId].reward);
        }
    }

    function getTest(uint testId) public view testExist(testId) returns (uint startTime,
        uint finishTime,
        string scenario,
        uint reward,
        bool isRewardPaid,
        TestStatus status,
        bool amITester) {
        Test storage test = _tests[testId];
        startTime = test.startTime;
        finishTime = test.finishTime;
        scenario = test.scenario;
        reward = test.reward;
        isRewardPaid = test.isRewardPaid;
        status = test.status;
        amITester = _testerStates[testId][msg.sender] != TesterState.NONE;
    }

    function getMyTests() public view returns (string tests) {
        for(uint i = 0; i < _tests.length; i++) {
            if(_tests[i].owner == msg.sender) {
                tests = StringUtils.strConcat(tests, ",", StringUtils.uint2str(i));
            }
        }
        return tests;
    }

    //TODO oprimize
    //Test state calculation depending on tester's states
    function calculateTestNewState(uint testId) internal returns (TestStatus status) {
        Test storage _test = _tests[testId];
        uint testersCount = _test.testers.length;
        uint attachedCount;
        uint readyCount;
        uint finishedCount;
        for(uint i = 0; i < testersCount; i++) {
            TesterState _testerState = _testerStates[testId][_test.testers[i]];
            if(_testerState == TesterState.ATTACHED) {
                attachedCount++;
            } else if(_testerState == TesterState.READY) {
                readyCount++;
            } else if(_testerState == TesterState.FINISHED) {
                finishedCount++;
            }
        }

        if(readyCount == testersCount && _test.status != TestStatus.RUNNING) {
            if(_testsResults[testId].length > 0 && _test.status == TestStatus.READY) {
                status = TestStatus.RUNNING;
            } else {
                status = TestStatus.READY;
            }
        } else if(finishedCount == testersCount){
            status = TestStatus.FINISHED;
        } else {
            status = _test.status;
        }

        if(status != _tests[testId].status) {
            _tests[testId].status = status;
            if(status == TestStatus.FINISHED) {
                _tests[testId].finishTime = now;
            }
            emit TestStatusChanged(testId, status);
        }
    }

    //Modifiers
    modifier onlyTestOwner(uint testId) {
        require(_tests[testId].owner == msg.sender, "You are not a test owner!");
        _;
    }

    modifier onlyTester(uint testId) {
        require(_testerStates[testId][msg.sender] != TesterState.NONE, "You are not a tester in this test");
        _;
    }

    modifier testExist(uint testId) {
        require(testId >= 0 && testId < _tests.length, "Test does not exist");
        _;
    }

    modifier testerAtState(uint testId, TesterState state) {
        require(_testerStates[testId][msg.sender] == state, "Invalid tester state");
        _;
    }

    modifier testAtStatus(uint testId, TestStatus status) {
        require(_tests[testId].status == status ,"Invalid status of the test");
        _;
    }

    // System Events
    // Fired when new test created
    event TestCreated(
        uint _id,
        uint _reward
    );
    // Fired when test status changed
    event TestStatusChanged(
        uint _id,
        TestStatus status
    );
    // Fired when tester state changed for specific test
    event TesterSateChanged(
        uint _id,
        TesterState state
    );
}


contract TesterOperations is TestOperations {

    function getTestsForTest() public view returns (string tests) {
        for(uint i = 0; i < _tests.length; i++) {
            if(_testerStates[i][msg.sender] != TesterState.NONE) {
                tests = StringUtils.strConcat(tests, ",", StringUtils.uint2str(i));
            }
        }
        return tests;
    }
    //Tester should call this method before test starts
    function announceReadiness(uint testId, bool isReady) public testExist(testId)
    onlyTester(testId)
    testAtStatus(testId, TestStatus.WAITING)
    returns (TestStatus status) {
        _testerStates[testId][msg.sender] = isReady ? TesterState.READY : TesterState.ATTACHED;
        emit TesterSateChanged(testId, _testerStates[testId][msg.sender]);

        status = calculateTestNewState(testId);
    }

    function pushTestResult(uint testId, string result)  public testExist(testId)
    onlyTester(testId)
    testerAtState(testId, TesterState.READY)
    returns (TestStatus status) {
        //require(_tests[testId].startTime <= now, "Test don't start yet");
        require(_tests[testId].status == TestStatus.READY || _tests[testId].status == TestStatus.RUNNING,
            "Test in invalid status");

        _testsResults[testId].push(result);

        status = calculateTestNewState(testId);
    }

    //Tester should call this method when he finished test
    //check that exactly this tester had published some test result before call this method
    function finishTest(uint testId)  public testExist(testId)
    onlyTester(testId)
    testerAtState(testId, TesterState.READY)
    testAtStatus(testId, TestStatus.RUNNING)
    returns (TestStatus status) {

        require(_testsResults[testId].length > 0, "It is impossible to finish test before the results are in");

        _testerStates[testId][msg.sender] = TesterState.FINISHED;
        emit TesterSateChanged(testId, TesterState.FINISHED);

        status = calculateTestNewState(testId);
    }


    function getReward(uint testId) public onlyTester(testId) {
        require(_tests[testId].finishTime > now + 7 * 24 * 60 * 60, "Tester can get reward by his own, if test finished 7 days ago");
        payReward(testId);
    }
}

contract CustomerOperations is TesterOperations {

    function getTesterStates(uint testId) public view
    onlyTestOwner(testId)
    testExist(testId)
    returns (string testers) {
        Test memory test = _tests[testId];
        for(uint i = 0; i < test.testers.length; i++) {
            testers = StringUtils.strConcat(testers, ",", StringUtils.uint2str(i));
            testers = StringUtils.strConcat(testers, ":", StringUtils.uint2str(uint(_testerStates[testId][test.testers[i]])));
        }
    }

    function getTestResults(uint testId) public view
    onlyTestOwner(testId)
    testExist(testId) returns (string results){
        string[] memory testResults = _testsResults[testId];
        for(uint i = 0; i < testResults.length; i++) {
            results = StringUtils.strConcat(results, ",", testResults[i]);
        }
    }

    function rewardTesters(uint testId) public onlyTestOwner(testId) {
        payReward(testId);
    }
}
