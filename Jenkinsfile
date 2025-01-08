@Library('xmos_jenkins_shared_library@v0.35.0') _

def run_tests(cmake_ver, generator) {
  createVenv('python_version.txt')
  withVenv {
    sh 'pip install -r requirements.txt'
    script {
      if ("${cmake_ver}" == 'latest') {
        sh 'pip install cmake'
      }
      else {
        sh "pip install cmake==${cmake_ver}"
      }
    }

    dir('tests') {
      withTools(params.TOOLS_VERSION) {
        withEnv(["XMOS_CMAKE_PATH=${WORKSPACE}"]) {
          sh "pytest -n auto --junitxml=pytest_result.xml -k ${generator}"
        }
      }
    }
  }
}

def os_label = [
    linux: 'linux && x86_64',
    macos: 'macos && arm64',
    windows: 'windows && x86_64',
]

getApproval()

pipeline {
  agent none
  options {
    timestamps()
    buildDiscarder(xmosDiscardBuildSettings(onlyArtifacts=false))
  }
  parameters {
    string(
      name: 'TOOLS_VERSION',
      defaultValue: '15.3.0',
      description: 'The XTC Tools version'
    )
    string(
      name: 'XMOSDOC_VERSION',
      defaultValue: 'v6.2.0',
      description: 'The xmosdoc version'
    )
  }

  stages {
    stage('Documentation') {
      agent {
        label 'linux && x86_64'
      }
      steps {
        println "Stage running on ${env.NODE_NAME}"
        buildDocs()
      }
      post {
        cleanup {
          xcoreCleanSandbox()
        }
      }
    }
    stage('Test') {
      matrix {
        axes {
          axis {
            name 'PLATFORM'
            values 'linux', 'macos', 'windows'
          }
          axis {
            name 'CMAKE_VERSION'
            values '3.21.0', 'latest'
          }
          axis {
            name 'GENERATOR'
            values 'generator0', 'generator1'
          }
        }
        stages {
          stage("Test") {
            agent {
              label "${os_label[env.PLATFORM]}"
            }
            steps {
              println "Stage running on ${env.NODE_NAME}"
              run_tests("${CMAKE_VERSION}", "${GENERATOR}")
            }
            post {
              always {
                junit 'tests/pytest_result.xml'
              }
              cleanup {
                xcoreCleanSandbox()
              }
            }
          }
        }
      }
    }
  }
}
