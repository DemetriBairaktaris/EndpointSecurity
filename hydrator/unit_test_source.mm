//
//  unit_test_source.cpp
//  hydrator
//
//  Created by admin on 6/10/20.
//  Copyright © 2020 admin. All rights reserved.
//

#define CATCH_CONFIG_MAIN
#include "unit_test_source.hpp"
#include "Catch2.hpp"


using namespace unit_test{
    static bool is_testable(){
        return true;
    }
}

unsigned int Factorial( unsigned int number ) {
    return number <= 1 ? number : Factorial(number-1)*number;
}

TEST_CASE( "Factorials are computed", "[factorial]" ) {
    REQUIRE( Factorial(1) == 1 );
    REQUIRE( Factorial(2) == 2 );
    REQUIRE( Factorial(3) == 6 );
    REQUIRE( Factorial(10) == 3628800 );
}




