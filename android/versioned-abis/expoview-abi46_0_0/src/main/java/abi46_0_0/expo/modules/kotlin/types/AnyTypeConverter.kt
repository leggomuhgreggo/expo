package abi46_0_0.expo.modules.kotlin.types

import abi46_0_0.com.facebook.react.bridge.Dynamic
import abi46_0_0.com.facebook.react.bridge.ReadableType
import abi46_0_0.expo.modules.kotlin.jni.CppType

/**
 * Type converter that handles conversion from [Any] or [Dynamic] to [Any].
 * In the first case, it will just pass provided value.
 * In case when it receives [Dynamic], it will unpack the provided value.
 * In that way, we produce the same output for JSI and bridge implementation.
 */
class AnyTypeConverter(isOptional: Boolean) : DynamicAwareTypeConverters<Any>(isOptional) {
  override fun convertFromDynamic(value: Dynamic): Any {
    return when (value.type) {
      ReadableType.Boolean -> value.asBoolean()
      ReadableType.Number -> value.asDouble()
      ReadableType.String -> value.asString()
      ReadableType.Map -> value.asMap()
      ReadableType.Array -> value.asArray()
      else -> error("Unknown dynamic type: ${value.type}")
    }
  }

  override fun convertFromAny(value: Any): Any {
    return value
  }

  override fun getCppRequiredTypes(): List<CppType> = listOf(
    CppType.READABLE_MAP,
    CppType.READABLE_ARRAY,
    CppType.STRING,
    CppType.BOOLEAN,
    CppType.DOUBLE
  )
}
