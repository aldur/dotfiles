package io.github.aldur.avfsshagent.core;

/** Runs all tests. The first failure ends the process with exit status 1. */
final class AllTests {
    private AllTests() {}

    public static void main(String[] args) throws Exception {
        CodecTest.main(args);
        KeysTest.main(args);
        SessionTest.main(args);
        ClientTest.main(args);
        System.out.println("ALL TESTS PASSED");
    }
}
